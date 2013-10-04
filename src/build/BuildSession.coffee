fs = require('fs')
path = require('path')
requirejs = require('requirejs')

Future = require('../utils/Future')

buildManager = require('./BuildManager')
fileInfo = require('./FileInfo')


class BuildSession
  ###
  Organizes build of the applied files in the right order sequence in terms of cordjs framework.
  ###

  @APP_CONF_FILE: 'public/app/application'

  _completePromise: null
  _corePromise: null
  _widgetClassesPromise: null
  _appConfPromise: null
  _pathUtilsPromise: null
  _relativePos: 0


  constructor: (@params) ->
    @_relativePos = @params.baseDir.length + 1
    @_completePromise = new Future(1)
    @_corePromise = new Future(1)
    @_widgetClassesPromise = new Future(1)
    @_appConfPromise = new Future(1)
    @_pathUtilsPromise = new Future(1)
    @_completePromise.when(@_appConfPromise, @_pathUtilsPromise)


  add: (file) ->
    ###
    Adds file to the build session
    @param String file absolute file path
    @return Future
    ###
    file = file.substr(@_relativePos)
    if file == BuildSession.APP_CONF_FILE + '.coffee'
      @_appConfPromise.fork()
      @_handleFile(file).done =>
        requirejs.config
          baseUrl: @params.targetDir
        requirejs [BuildSession.APP_CONF_FILE], (bundles) =>
          @_handleBundlesChange(bundles)
          @_appConfPromise.resolve()
    else if file == BuildSession.PATH_UTILS_FILE
      @_handleFile(file, 'cord/core').link(@_pathUtilsPromise)
    else
      @_appConfPromise.andThen =>
        @_handleFile(file, fileInfo.detectBundle(file)).link(@_completePromise)
      .link(@_completePromise)


  complete: ->
    ###
    Indicates that all files are added for this session.
    @return Future completes when the build session is completed
    ###
    @_appConfPromise.resolve()
    @_pathUtilsPromise.resolve()
    @_corePromise.resolve()
    @_widgetClassesPromise.resolve()
    @_completePromise.resolve()
    @_completePromise


  _handleBundlesChange: (bundles) ->
    ###
    Calculates bundles diff, removes old bundles from build, adds new bundles files to build
    ###
    # stub


  _handleFile: (file, bundle) ->
    info = fileInfo.getFileInfo(file, bundle)
    if info.isStylus
      @_pathUtilsPromise.flatMap =>
        @_createTask(file, info)
    else if info.inWidgets
      if info.isWidget
        @_corePromise.flatMap =>
          @_createTask(file, info)
        .link(@_widgetClassesPromise)
      else if info.isWidgetTemplate
        @_widgetClassesPromise.flatMap =>
          @_createTask(file, info)
      else
        @_createTask(file, info)
    else if bundle == 'cord/core'
      @_createTask(file, info).link(@_corePromise)
    else
      @_createTask(file, info)


  _createTask: (file, info) ->
    @_sourceModified(file, info).flatMap (modified) =>
      if modified
        buildManager.createTask(file, @params.baseDir, @params.targetDir, info)
      else
        Future.resolved()


  _sourceModified: (file, info) ->
    ###
    Asynchronously returns true if destination built file modification time is earlier than the source
     (file need to be recompiled)
    @param String file relative file name
    @param Object info framework-related information about the file
    @return Future[Boolean]
    ###
    srcPath = path.join(@params.baseDir, file)
    dstPath = path.join(@params.targetDir, fileInfo.getBuildDestinationFile(file, info))
    Future.call(fs.stat, srcPath).zip(Future.call(fs.stat, dstPath)).map (srcStat, dstStat) ->
      srcStat.mtime.getTime() > dstStat.mtime.getTime()
    .mapFail ->
      true



module.exports = BuildSession
