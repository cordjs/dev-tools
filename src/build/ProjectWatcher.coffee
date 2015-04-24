{EventEmitter} = require 'events'
fs             = require 'fs'
path           = require 'path'

_ = require 'underscore'

Future = require '../utils/Future'


class ProjectWatcher extends EventEmitter
  ###
  Directory tree watcher wrapper.
  Emits aggregated 'change' event when some watched files/directories are added/removed/moved
  ###

  _watchTree: null
  _fileByInode: null
  _inodeByFile: null

  _analyzeList: null
  _aggregateTimeout: null
  _previousAnalyzeAndEmit: null

  _watcher: null


  constructor: (@baseDir) ->
    rootInfo =
      dir: @baseDir
      watchAll: false
      children: {}
      contents: null
      watcher: null # base directory has no files to watch, watching for changes of server.coffee is not supported

    @_watchTree = rootInfo

    @_analyzeList = {}

    @_previousAnalyzeAndEmit = Future.resolved()

    # pathwatcher is preferred watching library, but if it's not installed, using standard buggy (in OS-X) fs.watch
    @_watcher = try
      require 'pathwatcher'
    catch
      fs



  addDir: (dir) ->
    if dir.indexOf(@baseDir) == 0
      parts = dir.substr(@baseDir.length).split('/')
      parts = _.compact(parts)
      curParent = @_watchTree
      try
        for part in parts
          curParent = @_watchDir(curParent, part)
        curParent.watchAll = true
      catch err
        console.error "Watch failed for the directory [#{curParent.dir}/#{part}], reason:", err
    else
      throw new Error("Watch directory #{dir} must be sub-directory of base dir #{@baseDir}!")


  _watchDir: (parentInfo, localName) ->
    if parentInfo.children[localName]?
      parentInfo.children[localName]
    else
      dir = path.join(parentInfo.dir, localName)
      watchInfo =
        dir: dir
        watchAll: false
        children: {}
        contents: @_readdir(dir)
        watcher: @_watcher.watch dir, (event, filename) =>
          @_handleDir(watchInfo, filename, event)
      parentInfo.children[localName] = watchInfo
      watchInfo


  _readdir: (dir) ->
    ###
    Collects stat-info of all shallow members of the given directory.
    @param String dir absolute directory path
    @return Future[Map[String -> StatInfo]]
    ###
    Future.call(fs.readdir, dir).flatMap (dirList) ->
      fList = for name in dirList
        do (name) ->
          Future.call(fs.lstat, path.join(dir, name)).map (stat) ->
            stat.name = name
            stat
      Future.sequence(fList).map (statList) ->
        result = {}
        for stat in statList
          result[stat.name] = stat
        result


  _handleDir: (watchInfo, filename, event) ->
    #console.log "watch event", event, filename, watchInfo.dir
    @_analyzeDir(watchInfo)


  _analyzeDir: (watchInfo) ->
    ###
    Collects directories to be analyzed together to emit one 'change' event
    ###
    @_analyzeList[watchInfo.dir] = watchInfo
    @_activateAggregateTimeout()


  _activateAggregateTimeout: ->
    clearTimeout(@_aggregateTimeout) if @_aggregateTimeout?
    @_aggregateTimeout = setTimeout =>
      tmpList = @_analyzeList
      @_analyzeList = {}
      @_aggregateTimeout = null
      previous = @_previousAnalyzeAndEmit
      current = Future.single()
      @_previousAnalyzeAndEmit = current
      previous.done =>
        current.when(@_analyzeAndEmit(tmpList))
    , 100


  _analyzeAndEmit: (dirList) ->
    ###
    Analyzes list of directories by diffing their current contents with the saved previous contents and
     emits appropriate 'change' event consumed by project builder
    @param Map[String -> Object]
    @return Future
    ###
    #console.log 'aggregated watch event', _.keys(dirList).map (d) => d.substr(@baseDir.length + 1)
    result = new Future
    summaryChangeMap = {}
    summaryRemoveList = []
    for dir, watchInfo of dirList
      do (dir, watchInfo) =>
        result.fork()
        newContents = @_readdir(dir)
        oldContents = watchInfo.contents
        watchInfo.contents = newContents
        # get current contents of the directory and calculate the difference with the previous contents
        oldContents.zip(newContents).done (oldMap, newMap) =>
          oldItems = Object.keys(oldMap)
          newItems = Object.keys(newMap)

          removeList = _.difference(oldItems, newItems)
          addList = _.difference(newItems, oldItems)

          changeList = []
          for name in _.intersection(newItems , oldItems)
            newStat = newMap[name]
            oldStat = oldMap[name]
            if newStat.mtime.getTime() != oldStat.mtime.getTime()
              if (newStat.isDirectory() and not oldStat.isDirectory()) or \
                 (not newStat.isDirectory() and oldStat.isDirectory())
                # if it was a file and become a directory or in opposite way, then we need to remove previous
                removeList.push(name)
                addList.push(name)
              else if not newStat.isDirectory() and not oldStat.isDirectory()
                # directories can't be changed, they can be only removed or added
                changeList.push(name)

          changeMap = {}
          if watchInfo.watchAll
            # ignoring changes if this directory is not fully watched
            for name in addList.concat(changeList)
              changeMap[path.join(dir, name).replace(/\\/g, '/')] = newMap[name]

          removeListFiltered = []
          for name in removeList
            # ignoring directories that are not watched
            if watchInfo.watchAll or watchInfo.children[name]?
              # cleaning watch descriptors of the removed directories
              @_stopWatching(watchInfo.children[name]) if watchInfo.children[name]?
              removeListFiltered.push(path.join(dir, name).replace(/\\/g, '/'))

          _.extend(summaryChangeMap, changeMap)
          summaryRemoveList = summaryRemoveList.concat(removeListFiltered)

          result.resolve()

        .fail (err) =>
          if err.code == 'ENOENT'
            # in case of recursive directory removing this error is usual and actually not an error
            @_stopWatching(watchInfo)
            result.resolve()
          else
            console.error "ERROR: readdir failed", watchInfo, err
            throw err
    result.done =>
      if Object.keys(summaryChangeMap).length > 0 or summaryRemoveList.length > 0
        @emit 'change',
          removed: summaryRemoveList
          changed: summaryChangeMap


  _stopWatching: (watchInfo) ->
    watchInfo.watcher?.close()
    watchInfo.watcher = null
    @_stopWatching(child) for name, child of watchInfo.children
    watchInfo.children = {}



module.exports = ProjectWatcher
