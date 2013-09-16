path = require('path')
requirejs = require('requirejs')
walk = require('walk')
{EventEmitter} = require('events')
Future = require('../utils/Future')
buildManager = require('./BuildManager')


class ProjectBuilder extends EventEmitter
  ###
  Builds the whole cordjs application project
  ###

  constructor: (@params) ->
    console.log "build params", @params


  build: ->
    console.log "building project..."

    start = process.hrtime()

    completePromise = new Future(1)
    corePromise = new Future(1)
    widgetClassesPromise = new Future(1)
    relativePos = @params.baseDir.length + 1


    scanDir = (dir, payloadCallback) ->
      completePromise.fork()
      walker = walk.walk(dir)
      walker.on 'file', (root, stat, next) =>
        if   root.indexOf('.git') < 0 and stat.name.indexOf('.git') < 0 \
         and root.indexOf('.hg') < 0 and stat.name.indexOf('.hg') < 0
          relativeDir = root.substr(relativePos)
          payloadCallback("#{relativeDir}/#{stat.name}", stat)
          setTimeout next, 0
        else
          next()

      walker.on 'end', ->
        console.log "walker for dir #{ dir } completed!"
        completePromise.resolve()
      walker


    scanRegularDir = (dir) =>
      scanDir dir, (relativeName) =>
        completePromise.when(
          buildManager.createTask(relativeName, @params.baseDir, @params.targetDir, getFileInfo(relativeName))
        )


    scanCore = =>
      scanDir "#{ @params.baseDir }/public/bundles/cord/core", (relativeName) =>
        info = getFileInfo(relativeName, 'cord/core')
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
      .on 'end', ->
        corePromise.resolve()


    scanBundle = (bundle) =>
      widgetClassesPromise.fork()
      scanDir "#{ @params.baseDir }/public/bundles/#{ bundle }", (relativeName) =>
        info = getFileInfo(relativeName, bundle)
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
      .on 'end', ->
        widgetClassesPromise.resolve()


    appConfFile = 'public/app/application'

    appConfPromise = buildManager.createTask(
      "#{ appConfFile }.coffee", @params.baseDir, @params.targetDir,
      getFileInfo("#{ appConfFile }.coffee")
    )
    pathUtilsPromise = buildManager.createTask(
      'public/bundles/cord/core/requirejs/pathUtils.coffee',
      @params.baseDir, @params.targetDir,
      getFileInfo('public/bundles/cord/core/requirejs/pathUtils.coffee', 'cord/core')
    )
    scanRegularDir(@params.baseDir + '/public/vendor')
    scanRegularDir(@params.baseDir + '/conf')
    #scanRegularDir(@params.baseDir + '/node_modules')
    buildManager.createTask('server.coffee', @params.baseDir, @params.targetDir, getFileInfo('server.coffee'))
      .link(completePromise)

    appConfPromise.done =>
      scanCore()
      requirejs.config
        baseUrl: @params.targetDir
      requirejs [appConfFile], (bundles) ->
        for bundle in bundles
          scanBundle(bundle)
        widgetClassesPromise.resolve()
        completePromise.resolve()

    completePromise.done ->
      diff = process.hrtime(start)
      console.log "Build complete in #{ (diff[0] * 1e9 + diff[1]) / 1e6 } ms"
      buildManager.stop()

    this



getFileInfo = (file, bundle) ->
  ###
  Returns a lot of file properties from the framework's point of view
  @param String file path to file
  @param (optional)String bundle bundle to which this file belongs
  @return Object key-value with file properties
  ###
  parts = file.split(path.sep)
  inPublic = parts[0] == 'public'
  fileName = parts.pop()
  lastDirName = parts[parts.length - 1]
  ext = path.extname(fileName)
  fileWithoutExt = fileName.slice(0, -ext.length)
  if inPublic
    inBundles = parts[1] == 'bundles'
    if inBundles
      bundleParts = bundle.split('/')
      bundleOk = true
      for p, i in bundleParts
        if p != parts[2 + i]
          bundleOk = false
          break
      if bundleOk
        inBundleIndex = 2 + bundleParts.length
        inWidgets = parts[inBundleIndex] == 'widgets'
        inTemplates = parts[inBundleIndex] == 'templates'
        inModels = parts[inBundleIndex] == 'models'
        if inWidgets
          if ext == '.coffee'
            lowerName = fileWithoutExt.charAt(0).toLowerCase() + fileWithoutExt.slice(1)
            isWidget = lastDirName == lowerName
            isBehaviour = (lastDirName + 'Behaviour') == lowerName
          else if ext == '.html'
            isWidgetTemplate = lastDirName == fileWithoutExt
    else
      bundle = null

  fileName: fileName
  ext: ext
  fileNameWithoutExt: fileWithoutExt
  lastDirName: lastDirName
  bundle: bundle
  inPublic: inPublic
  inBundles: inBundles ? false
  inWidgets: inWidgets ? false
  inTemplates: inTemplates ? false
  inModels: inModels ? false
  isWidget: isWidget ? false
  isBehaviour: isBehaviour ? false
  isWidgetTemplate: isWidgetTemplate ? false
  isCoffee: ext == '.coffee'
  isHtml: ext == '.html'
  isStylus: ext == '.styl'



module.exports = ProjectBuilder
