path = require('path')
fs = require('fs')
requirejs = require('requirejs')
walk = require('walk')
{EventEmitter} = require('events')
_ = require('underscore')
Future = require('../utils/Future')
rmrf = require('../utils/rmrf')
buildManager = require('./BuildManager')
fileInfo = require('./FileInfo')
ProjectWatcher = require('./ProjectWatcher')


class ProjectBuilder extends EventEmitter
  ###
  Builds the whole cordjs application project
  ###

  constructor: (@params) ->
    console.log "build params", @params
    fileInfo.setDirs(@params.baseDir, @params.targetDir)
    @setupWatcher() if @params.watch


  build: ->
    console.log "building project..."

    start = process.hrtime()

    completePromise = new Future(1)
    corePromise = new Future(1)
    widgetClassesPromise = new Future(1)
    relativePos = @params.baseDir.length + 1


    scanDir = (dir, payloadCallback) =>
      @watchDir(dir)

      completePromise.fork()
      walker = walk.walk(dir)
      walker.on 'file', (root, stat, next) =>
        if   root.indexOf('.git') < 0 and stat.name.indexOf('.git') < 0 \
         and root.indexOf('.hg') < 0 and stat.name.indexOf('.hg') < 0
          @watchFile("#{root}/#{stat.name}", stat)
          relativeDir = root.substr(relativePos)
          payloadCallback("#{relativeDir}/#{stat.name}", stat)
          setTimeout next, 0
        else
          next()

      if (@params.watch)
        walker.on 'directory', (root, stat, next) =>
          if   root.indexOf('.git') < 0 and stat.name.indexOf('.git') < 0 \
           and root.indexOf('.hg') < 0 and stat.name.indexOf('.hg') < 0
            @watchDir("#{root}/#{stat.name}", stat)
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
          completePromise.resolve()
      .on 'end', ->
        widgetClassesPromise.resolve()


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
        completePromise.resolve()

    completePromise.done ->
      diff = process.hrtime(start)
      console.log "Build complete in #{ (diff[0] * 1e9 + diff[1]) / 1e6 } ms"
      buildManager.stop()

    this


  setupWatcher: ->
    @watcher = new ProjectWatcher(@params.baseDir)
    @watcher.on 'change', (changes) ->
      console.log "change", changes
      for removed in _.sortBy(changes.removed, (f) -> f.length).reverse()
        console.log "removing #{removed}..."
        rmrf(fileInfo.getTargetForSource(removed)).failAloud()


  watchDir: (dir, stat) ->
    @watcher.addDir(dir, stat) if @params.watch


  watchFile: (file, stat) ->
    @watcher.registerFile(file, stat) if @params.watch



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
