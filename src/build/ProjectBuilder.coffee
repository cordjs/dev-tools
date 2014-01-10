path = require('path')
fs = require('fs')
requirejs = require('requirejs')
{EventEmitter} = require('events')
_ = require('underscore')

Future = require('../utils/Future')
rmrf = require('../utils/rmrf')
fswalker = require '../utils/fswalker'

buildManager = require('./BuildManager')
BuildSession = require('./BuildSession')
fileInfo = require('./FileInfo')
ProjectWatcher = require('./ProjectWatcher')


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
      dir.indexOf(path.sep + '.') == -1
  res


class ProjectBuilder extends EventEmitter
  ###
  Builds the whole cordjs application project
  ###

  _emitCompletePromise: null

  constructor: (@params) ->
    fileInfo.setDirs(@params.baseDir, @params.targetDir)
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
      completePromise.done => @watchDir(dir)

      completePromise.fork()
      walker = fswalker(dir, filter: walkerFilter)
      walker.on 'file', (root, stat, next) =>
        relativeDir = root.substr(relativePos)
        payloadCallback("#{relativeDir}/#{stat.name}", stat)
        setTimeout next, 0

      walker.on 'symbolicLink', (root, stat, next) =>
        relativeDir = root.substr(relativePos)
        payloadCallback("#{relativeDir}/#{stat.name}", stat)
        next()

      if (@params.watch)
        walker.on 'directory', (root, stat, next) =>
          completePromise.done => @watchDir("#{root}/#{stat.name}")
          next()

      walker.on 'end', ->
        console.log "walker for dir #{ dir } completed!"
        completePromise.resolve()
      walker


    scanRegularDir = (dir) =>
      scanDir dir, (relativeName, stat) =>
        info = fileInfo.getFileInfo(relativeName)
        completePromise.fork()
        sourceModified(relativeName, stat, @params.targetDir, info).map (modified) =>
          if modified
            completePromise.when(
              buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
            )
          completePromise.resolve()


    scanCore = =>
      scanDir "#{ @params.baseDir }/public/bundles/cord/core", (relativeName, stat) =>
        info = fileInfo.getFileInfo(relativeName, 'cord/core')
        completePromise.fork()
        sourceModified(relativeName, stat, @params.targetDir, info).map (modified) =>
          if modified
            if info.inWidgets
              if info.isWidget
                task = corePromise.flatMap =>
                  buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                completePromise.when(task)
                widgetClassesPromise.when(task)
              else if info.isWidgetTemplate
                widgetClassesPromise.flatMap =>
                  buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
              else if info.isStylus
                pathUtilsPromise.flatMap =>
                  buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
              else
                buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                  .link(completePromise)
            else
              task = buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
              corePromise.when(task)
              completePromise.when(task)
          completePromise.resolve()
        .link(corePromise)
      .on 'end', ->
        corePromise.resolve()


    scanBundle = (bundle) =>
      widgetClassesPromise.fork()
      nonWidgetFilesPromise.fork()
      scanDir "#{ @params.baseDir }/public/bundles/#{ bundle }", (relativeName, stat) =>
        info = fileInfo.getFileInfo(relativeName, bundle)
        completePromise.fork()
        sourceModified(relativeName, stat, @params.targetDir, info).map (modified) =>
          if modified
            if info.isWidget
              task = corePromise.flatMap =>
                buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
              completePromise.when(task)
              widgetClassesPromise.when(task)
            else if info.isWidgetTemplate
              widgetClassesPromise.zip(nonWidgetFilesPromise).flatMap =>
                buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
              .link(completePromise)
            else if info.isCoffee and not info.inWidgets
              buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
                .link(nonWidgetFilesPromise)
            else if info.isStylus
              pathUtilsPromise.flatMap =>
                buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
              .link(completePromise)
            else
              buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, info)
                .link(completePromise)
          completePromise.resolve()
      .on 'end', ->
        widgetClassesPromise.resolve()
        nonWidgetFilesPromise.resolve()


    appConfFile = 'public/app/application'

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

    appConfPromise.done =>
      scanCore()
      requirejs.config
        baseUrl: @params.targetDir
      requirejs [appConfFile], (bundles) ->
        fileInfo.setBundles(bundles)
        for bundle in bundles
          scanBundle(bundle)
        widgetClassesPromise.resolve()
        nonWidgetFilesPromise.resolve()
        completePromise.resolve()

    completePromise.done =>
      diff = process.hrtime(start)
      console.log "Build complete in #{ (diff[0] * 1e9 + diff[1]) / 1e6 } ms"
      buildManager.stop()
      @emit 'complete'

    @_previousSessionPromise = completePromise

    this


  setupWatcher: ->
    @watcher = new ProjectWatcher(@params.baseDir)
    @watcher.on 'change', (changes) =>
      if not @_emitCompletePromise?
        @_emitCompletePromise = new Future
        @_emitCompletePromise.fork()
        @_emitCompletePromise.done =>
          @emit 'complete'
          @_emitCompletePromise = null
      else
        @_emitCompletePromise.fork()
      currentSessionPromise = @_previousSessionPromise.flatMap =>
        rmList = for removed in _.sortBy(changes.removed, (f) -> f.length).reverse()
          console.log "removing #{removed}..."
          rmrf(fileInfo.getTargetForSource(removed)).failAloud()

        Future.sequence(rmList).flatMap =>
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
              sessionCompletePromise.done => @watchDir("#{root}/#{stat.name}")
              next()

            walker.on 'end', ->
              console.log "walker for dir #{ dir } completed!"
              result.resolve()

            result

          scanCompletePromise = new Future
          for file, stat of changes.changed
            if stat.isFile()
              buildSession.add(file)
            else if stat.isDirectory()
              scanCompletePromise.when(scanDir(file))
          scanCompletePromise.flatMap ->
            sessionCompletePromise.when(buildSession.complete())
          .done =>
            @_emitCompletePromise.resolve()

      @_previousSessionPromise = currentSessionPromise


  watchDir: (dir) ->
    @watcher.addDir(dir) if @params.watch



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
  Future.call(fs.stat, dstPath).map (dstStat) ->
    srcStat.mtime.getTime() > dstStat.mtime.getTime()
  .mapFail ->
    true



module.exports = ProjectBuilder
