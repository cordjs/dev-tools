path = require('path')
requirejs = require('requirejs')
walk = require('walk')
{EventEmitter} = require('events')
{Future} = require('../utils/Future')
{buildManager} = require('./BuildManager')


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

      walker.on 'end', ->
        console.log "walker for dir #{ dir } completed!"
        completePromise.resolve()
      walker


    scanRegularDir = (dir) =>
      scanDir dir, (relativeName) =>
        completePromise.when(
          buildManager.createTask(relativeName, @params.baseDir, @params.targetDir)
        )


    scanCore = =>
      scanDir "#{ @params.baseDir }/public/bundles/cord/core", (relativeName) =>
        if inWidgetsDir(relativeName)
          completePromise.when(
            corePromise.flatMap =>
              buildManager.createTask(relativeName, @params.baseDir, @params.targetDir)
          )
        else
          task = buildManager.createTask(relativeName, @params.baseDir, @params.targetDir)
          corePromise.when(task)
          completePromise.when(task)
      .on 'end', ->
        corePromise.resolve()


    scanBundle = (bundle) =>
      widgetClassesPromise.fork()
      scanDir "#{ @params.baseDir }/public/bundles/#{ bundle }", (relativeName) =>
        if isWidgetClass(relativeName, bundle)
          task = corePromise.flatMap =>
            buildManager.createTask(relativeName, @params.baseDir, @params.targetDir)
          completePromise.when(task)
          widgetClassesPromise.when(task)
        else if isWidgetTemplate(relativeName, bundle)
          widgetClassesPromise.flatMap =>
            buildManager.createTask(relativeName, @params.baseDir, @params.targetDir)
          .link(completePromise)
        else if isStylus(relativeName)
          pathUtilsPromise.flatMap =>
            buildManager.createTask(relativeName, @params.baseDir, @params.targetDir)
          .link(completePromise)
        else
          buildManager.createTask(relativeName, @params.baseDir, @params.targetDir)
            .link(completePromise)
      .on 'end', ->
        widgetClassesPromise.resolve()


    appConfFile = 'public/app/application'

    appConfPromise = buildManager.createTask("#{ appConfFile }.coffee", @params.baseDir, @params.targetDir)
    pathUtilsPromise = buildManager.createTask(
      'public/bundles/cord/core/requirejs/pathUtils.coffee',
      @params.baseDir, @params.targetDir
    )
    scanRegularDir(@params.baseDir + '/public/vendor')
    scanRegularDir(@params.baseDir + '/conf')
    #scanRegularDir(@params.baseDir + '/node_modules')
    completePromise.when(buildManager.createTask("server.coffee", @params.baseDir, @params.targetDir))

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



inWidgetsDir = (file) ->
  /public\/bundles\/.+\/widgets\//.test(file)

isWidgetClass = (file, bundle) ->
  ext = path.extname(file)
  if ext = '.coffee'
    if file.indexOf("public/bundles/#{bundle}/widgets/") == 0
      base = path.basename(file)
      name = base.slice(0, -ext.length)
      dir = file.substr(-(base.length + name.length + 1), name.length)
      dir = dir.charAt(0).toUpperCase() + dir.slice(1)
      dir == name
    else
      false
  else
    false

isCoffee = (file) ->
  path.extname(file) == '.coffee'

isStylus = (file) ->
  path.extname(file) == '.styl'

isWidgetTemplate = (file, bundle) ->
  ext = path.extname(file)
  if ext = '.html'
    if file.indexOf("public/bundles/#{bundle}/widgets/") == 0
      base = path.basename(file)
      name = base.slice(0, -ext.length)
      dir = file.substr(-(base.length + name.length + 1), name.length)
      dir == name
    else
      false
  else
    false



exports.ProjectBuilder = ProjectBuilder
