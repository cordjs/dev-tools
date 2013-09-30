path = require('path')
fs = require('fs')
_ = require('underscore')
{EventEmitter} = require('events')


class ProjectWatcher extends EventEmitter
  ###
  Directory tree watcher wrapper.
  Emits aggregated 'change' event when some watched files/directories are added/removed/moved
  ###

  @_watchTree: null
  @_fileByInode: null
  @_inodeByFile: null

  @_changedItems: null
  @_removedItems: null
  @_emitTimeout: null


  constructor: (@baseDir) ->
    rootInfo =
      dir: @baseDir
      watchAll: false
      children: {}
      watcher: fs.watch @baseDir, (event, filename) =>
        @_handleDir(rootInfo, filename, event)

    @_watchTree = rootInfo
    @_fileByInode = {}
    @_inodeByFile = {}

    @_changedItems = {}
    @_removedItems = {}


  addDir: (dir, stat) ->
    if dir.indexOf(@baseDir) == 0
      @_registerInode(dir, stat.ino) if stat?
      parts = dir.substr(@baseDir.length).split(path.sep)
      parts = _.compact(parts)
      curParent = @_watchTree
      for part in parts
        curParent = @_watchDir(curParent, part)
      curParent.watchAll = true
    else
      throw new Error("Watch directory #{dir} must be sub-directory of base dir #{@baseDir}!")


  registerFile: (file, stat) ->
    @_registerInode(file, stat.ino)


  _registerInode: (file, inode) ->
    if @_inodeByFile[file]? and inode != @_inodeByFile[file]
      delete @_fileByInode[@_inodeByFile[file]]
    if @_fileByInode[inode]? and file != @_fileByInode[inode]
      delete @_inodeByFile[@_fileByInode[inode]]
    @_fileByInode[inode] = file
    @_inodeByFile[file] = inode


  _watchDir: (parentInfo, localName) ->
    if parentInfo.children[localName]?
      parentInfo.children[localName]
    else
      dir = path.join(parentInfo.dir, localName)
      watchInfo =
        dir: dir
        watchAll: false
        children: {}
        watcher: fs.watch dir, (event, filename) =>
          @_handleDir(watchInfo, filename, event)
      parentInfo.children[localName] = watchInfo
      watchInfo


  _handleDir: (watchInfo, filename, event) ->
    if filename?
      console.log "watch event", event, filename
      fullName = path.join(watchInfo.dir, filename)
      fs.lstat fullName, (err, stat) =>
        if err
          if err.code == 'ENOENT'
            @_addRemoveItem(watchInfo, fullName)
          else
            console.error "stat error", err
        else
          # trying to detect if file was moved within the same directory or just changed
          # using saved inode as inode doesn't change when file is moved or renamed
          if (oldName = @_fileByInode[stat.ino])?
            if oldName == fullName
              @_addChangeItem(watchInfo, fullName, stat)
            else
              @_addChangeItem(watchInfo, fullName, stat)
              @_addRemoveItem(watchInfo, oldName)
          else
            @_addChangeItem(watchInfo, fullName, stat)
    else
      throw new Error("Filename is not supported in watch: #{ JSON.stringify(watchInfo) }!")


  _addChangeItem: (watchInfo, name, stat) ->
    localName = path.basename(name)
    if watchInfo.watchAll or watchInfo.children[localName]?
      @_changedItems[name] = stat
      delete @_removedItems[name] if @_removedItems[name]?
      @_activateEmitTimeout()


  _addRemoveItem: (watchInfo, name) ->
    localName = path.basename(name)
    if watchInfo.watchAll or watchInfo.children[localName]?
      @_removedItems[name] = true
      delete @_changedItems[name] if @_changedItems[name]?
      @_activateEmitTimeout()
      if watchInfo.children[localName]? and watchInfo.children[localName].watcher?
        @_stopWatching(watchInfo.children[localName])


  _activateEmitTimeout: ->
    clearTimeout(@_emitTimeout) if @_emitTimeout?
    @_emitTimeout = setTimeout =>
      if Object.keys(@_removedItems).length > 0 or Object.keys(@_changedItems).length > 0
        removeList = []
        removeList.push(name) for name of @_removedItems
        @emit 'change',
          removed: removeList
          changed: @_changedItems
        @_removedItems = {}
        @_changedItems = {}
        @_emitTimeout = null
    , 100


  _stopWatching: (watchInfo) ->
    watchInfo.watcher?.close()
    watchInfo.watcher = null
    @_stopWatching(child) for name, child of watchInfo.children
    watchInfo.children = {}



module.exports = ProjectWatcher
