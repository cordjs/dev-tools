path           = require 'path'
fs             = require 'fs'
{EventEmitter} = require 'events'
_              = require 'underscore'

normalizePathSeparator    = require '../utils/fsNormalizePathSeparator'

requirejs = require process.cwd() + '/node_modules/requirejs'

Future    = require '../utils/Future'
rmrf      = require '../utils/rmrf'
fswalker  = require '../utils/fswalker'

appConfig       = require '../appConfig'
requirejsConfig = require './task/requirejs-config'

buildManager   = require './BuildManager'
BuildSession   = require './BuildSession'
fileInfo       = require './FileInfo'
ProjectWatcher = require './ProjectWatcher'


walkerFilter = (dir, name) ->
  ###
  Filters hidden and temporary files from being handled by the builder.
  @param String dir dirname
  @param String name basename
  @return Boolean true if the file is OK for building, false if it should be skipped
  ###
  res = if name.charAt(0) == '.'
    false
  else
    ext = path.extname(name)
    if ext == '.orig' or ext.substr(-1) == '~'
      false
    else
      dir.indexOf('/.') == -1
  res


class ProjectBuilder extends EventEmitter
  ###
  Builds the whole cordjs application project
  ###

  _emitCompletePromise: null

  constructor: (@params) ->
    @params.baseDir = normalizePathSeparator(@params.baseDir)
    fileInfo.setDirs(@params.baseDir, @params.targetDir)
    buildManager.generateSourceMap = @params.map
    @setupWatcher() if @params.watch


  build: ->
    console.log "Building project (full scan)..."

    start = process.hrtime()

    completePromise = new Future(1)
    corePromise = new Future(1)
    widgetClassesPromise = new Future(1)
    nonWidgetFilesPromise = new Future(1)
    relativePos = @params.baseDir.length + 1


    scanDir = (dir, payloadCallback) =>
      dir = normalizePathSeparator(dir)
      completePromise.done => @watchDir(dir)

      completePromise.fork()
      walker = fswalker(dir, filter: walkerFilter)
      walker.on 'file', (root, stat, next) =>
        root = normalizePathSeparator(root)
        relativeDir = root.substr(relativePos)
        payloadCallback("#{relativeDir}/#{stat.name}", stat)
        setTimeout next, 0

      walker.on 'symbolicLink', (root, stat, next) =>
        root = normalizePathSeparator(root)
        relativeDir = root.substr(relativePos)
        payloadCallback("#{relativeDir}/#{stat.name}", stat)
        next()

      if (@params.watch)
        walker.on 'directory', (root, stat, next) =>
          root = normalizePathSeparator(root)
          completePromise.done => @watchDir("#{root}/#{stat.name}")
          next()

      walker.on 'end', ->
        console.log "walker for dir #{ dir } completed!" if false
        completePromise.resolve()
      walker


    scanRegularDir = (dir) =>
      scanDir dir, (relativeName, stat) =>
        info = fileInfo.getFileInfo(relativeName)
        completePromise.fork()
        sourceModified(relativeName, stat, @params.targetDir, info).then (modified) =>
          if modified
            completePromise.when(
              buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
            )
          completePromise.resolve()
          return


    scanCore = =>
      scanDir "#{ @params.baseDir }/public/bundles/cord/core", (relativeName, stat) =>
        info = fileInfo.getFileInfo(relativeName, 'cord/core')
        completePromise.fork()
        sourceModified(relativeName, stat, @params.targetDir, info).then (modified) =>
          if modified
            if info.inWidgets
              if info.isWidget
                corePromise.then =>
                  buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
                .link(widgetClassesPromise)
              else if info.isWidgetTemplate
                widgetClassesPromise.then =>
                  buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
              else if info.isStylus
                pathUtilsPromise.then =>
                  buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
              else
                buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                  .link(completePromise)
            else if not (info.fileName == 'pathUtils.coffee' and info.lastDirName == 'requirejs')
              buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(corePromise)
                .link(completePromise)
          completePromise.resolve()
          return
        .link(corePromise)
      .on 'end', ->
        corePromise.resolve()


    scanBundle = (bundle) =>
      widgetClassesPromise.fork()
      nonWidgetFilesPromise.fork()
      scanDir "#{ @params.baseDir }/public/bundles/#{ bundle }", (relativeName, stat) =>
        info = fileInfo.getFileInfo(relativeName, bundle)
        completePromise.fork()
        sourceModified(relativeName, stat, @params.targetDir, info).then (modified) =>
          if modified
            if info.isWidget
              corePromise.then =>
                buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
              .link(completePromise)
              .link(widgetClassesPromise)
            else if info.isWidgetTemplate
              Future.all([widgetClassesPromise, nonWidgetFilesPromise]).then =>
                buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
              .link(completePromise)
            else if info.isCoffee and not info.inWidgets
              buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
                .link(nonWidgetFilesPromise)
            else if info.isStylus
              pathUtilsPromise.then =>
                buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
              .link(completePromise)
            else
              buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
          completePromise.resolve()
          return
      .on 'end', ->
        widgetClassesPromise.resolve()
        nonWidgetFilesPromise.resolve()


    appConfFile = "public/app/#{@params.appConfigName}"

    appConfPromise = buildManager.createTask(
      "#{ appConfFile }.coffee", @params.baseDir, @params.targetDir,
      fileInfo.getFileInfo("#{ appConfFile }.coffee")
    )
    pathUtilsPromise = buildManager.createTask(
      'public/bundles/cord/core/requirejs/pathUtils.coffee',
      @params.baseDir, @params.targetDir,
      fileInfo.getFileInfo('public/bundles/cord/core/requirejs/pathUtils.coffee', 'cord/core')
    )
    scanRegularDir(@params.baseDir + '/public/vendor')
    scanRegularDir(@params.baseDir + '/conf')
    #scanRegularDir(@params.baseDir + '/node_modules')
    buildManager.createTask('server.coffee', @params.baseDir, @params.targetDir, fileInfo.getFileInfo('server.coffee'))
      .link(completePromise)

    buildManager.createTask(
      'optimizer-predefined-groups.coffee', @params.baseDir, @params.targetDir,
      fileInfo.getFileInfo('optimizer-predefined-groups.coffee')
    ).catch ->
      return # ignore errors
    .link(completePromise)

    appConfPromise.then =>
      scanCore()
      requirejs.config
        baseUrl: @params.targetDir
      appConfig.getBundles(@params.targetDir)
    .then (bundles) ->
      bundles = bundles.filter (n) -> n != 'cord/core'
      fileInfo.setBundles(bundles)
      scanBundle(bundle) for bundle in bundles
      widgetClassesPromise.resolve()
      nonWidgetFilesPromise.resolve()
      completePromise.resolve()
      return
    .failAloud()

    fullCompletePromise =
      if @params.indexPageWidget
        corePromise.then =>
          requirejsConfig(@params.targetDir)
        .then ->
          Future.all [
            Future.require('cord!requirejs/cord-w') # todo: find out - what is it for? (introduced with phonegap support)
            completePromise
          ]
        .then =>
          info =
            isIndexPage: true
            configName: @params.config
          buildManager.createTask(@params.indexPageWidget, @params.baseDir, @params.targetDir, info)
      else
        completePromise

    @_previousSessionPromise = fullCompletePromise.catch -> true

    showFinalMessage = (verb) ->
      diff = process.hrtime(start)
      console.log "Build #{verb} in #{ parseFloat((diff[0] * 1e9 + diff[1]) / 1e9).toFixed(3) } s"

    fullCompletePromise
      .catch (err) ->
        console.error "Build error", err, err.stack
        showFinalMessage('failed')
        throw err
      .then =>
        showFinalMessage('completed')
        buildManager.stop()
        @emit 'complete'
      .failAloud('ProjectBuilder::build')


  setupWatcher: ->
    @watcher = new ProjectWatcher(@params.baseDir)
    @watcher.on 'change', (changes) =>
      if not @_emitCompletePromise?
        console.log '====================='
        @_emitCompletePromise = new Future
        @_emitCompletePromise.fork()
        @_emitCompletePromise.done =>
          @emit 'complete'
          @_emitCompletePromise = null
      else
        @_emitCompletePromise.fork()
      currentSessionPromise = @_previousSessionPromise.then =>
        rmList = for removed in _.sortBy(changes.removed, (f) -> f.length).reverse()
          console.log "removing #{removed}..."
          rmrf(fileInfo.getTargetForSource(removed)).failAloud()

        Future.all(rmList).then =>
          buildSession = new BuildSession(@params)
          sessionCompletePromise = Future.single()

          scanDir = (dir) =>
            result = Future.single()
            sessionCompletePromise.done => @watchDir(dir)

            walker = fswalker(dir, filter: walkerFilter)
            walker.on 'file', (root, stat, next) =>
              buildSession.add(path.join(root, stat.name))
              next()

            walker.on 'symbolicLink', (root, stat, next) =>
              buildSession.add(path.join(root, stat.name))
              next()

            walker.on 'directory', (root, stat, next) =>
              sessionCompletePromise.done => @watchDir(normalizePathSeparator("#{root}/#{stat.name}"))
              next()

            walker.on 'end', ->
              console.log "walker for dir #{ dir } completed!" if false
              result.resolve()

            result

          scanCompletePromise = new Future
          for file, stat of changes.changed
            if stat.isFile()
              buildSession.add(file)
            else if stat.isDirectory()
              scanCompletePromise.when(scanDir(file))
          scanCompletePromise.then ->
            sessionCompletePromise.when(buildSession.complete())
        .then =>
          @_emitCompletePromise.resolve()

      @_previousSessionPromise = currentSessionPromise


  watchDir: (dir) ->
    @watcher.addDir(dir) if @params.watch


  buildIndex: ->
    ###
    Builds only `index.html` file for phonegap application.
    This task is need to be run after cordjs optimizer with --remove-sources option
     to avoid rebuilding project due to removed js sources.
    Project need to be completely build before this command can be run.
    ###
    if @params.indexPageWidget
      start = process.hrtime()
      requirejsConfig(@params.targetDir).then =>
        info =
          isIndexPage: true
          configName: @params.config
        buildManager.createTask(@params.indexPageWidget, @params.baseDir, @params.targetDir, info)

      .then -> 'completed'
      .catch (err) ->
        console.error "Build error", err, err.stack
        'failed'
      .then (verb) =>
        diff = process.hrtime(start)
        console.log "Build #{verb} in #{ parseFloat((diff[0] * 1e9 + diff[1]) / 1e9).toFixed(3) } s"
        if verb == 'completed'
          buildManager.stop()
          @emit 'complete'
      .failAloud('ProjectBuilder::buildIndex')

    else
      console.error "--index (-I) param is required for the 'buildIndex' command!"



sourceModified = (file, srcStat, targetDir, info) ->
  ###
  Asynchronously returns true if destination built file modification time is earlier than the source
   (file need to be recompiled)
  @param String file relative file name
  @param StatInfo srcStat result of stat-call for the source file
  @param String targetDir base directory for destination file
  @param Object info framework-related information about the file
  @return Future[Boolean]
  ###
  dstPath = path.join(targetDir, fileInfo.getBuildDestinationFile(file, info))
  Future.call(fs.stat, dstPath).then (dstStat) ->
    srcStat.mtime.getTime() > dstStat.mtime.getTime()
  .catch ->
    true



module.exports = ProjectBuilder
