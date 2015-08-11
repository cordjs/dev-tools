fs   = require 'fs'
path = require 'path'

requirejs = require process.cwd() + '/node_modules/requirejs'

Future = require '../utils/Future'
fsUtils = require '../utils/fsUtils'

buildManager = require './BuildManager'
fileInfo = require './FileInfo'


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
      @_appConfPromise.finally =>
        @_handleFile(file, fileInfo.detectBundle(file)).catch (err) ->
          console.error "Build task failed for\n#{file}", err, err.stack
          null
        .link(@_completePromise)
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
    if info.inWidgets
      isVdomWidget(file).then (vdomWidgetDirItems) =>
        if vdomWidgetDirItems
          @_createVdomWidgetTask(path.dirname(file), vdomWidgetDirItems, bundle)
        else
          if info.isWidget
            @_corePromise.then =>
              @_createTask(file, info)
            .link(@_widgetClassesPromise)
          else if info.isWidgetTemplate
            @_widgetClassesPromise.then =>
              @_createTask(file, info)
          else
            @_createTask(file, info)
    else if info.isStylus
      @_pathUtilsPromise.then =>
        @_createTask(file, info)
    else if bundle == 'cord/core'
      @_createTask(file, info).link(@_corePromise)
    else
      @_createTask(file, info)


  _createTask: (file, info) ->
    @_sourceModified(file, info).then (modified) =>
      if modified
        buildManager.createTask(file, @params.baseDir, @params.targetDir, info)
      else
        return


  _createVdomWidgetTask: (widgetDir, dirItems, bundle) ->
    ###
    Checks if any file of the given vdom-widget is modified and creates build task for it.
    @param {string} widgetDir - path to the vdom-widget directory
    @param {Object} dirItems - map of the widget directory item names with their fs.stats
    @param {string} bundle - the widget's bundle name
    @return {Promise.<undefined>|undefined}
    ###
    modified = (fileName) =>
      relativeName = "#{widgetDir}/#{fileName}"
      @_sourceModified(relativeName, fileInfo.getFileInfo(relativeName, bundle))

    lowerName = path.basename(widgetDir)
    upperName = lowerName.charAt(0).toUpperCase() + lowerName.slice(1)
    vdomTemplateFile = lowerName + '.vdom.html'
    widgetClassFile = upperName + '.coffee'
    stylusFile = lowerName + '.styl'
    if dirItems[widgetClassFile] and dirItems[widgetClassFile].isFile()
      modifiedPromises = [
        modified(widgetClassFile)
        modified(vdomTemplateFile)
      ]
      modifiedPromises.push(modified(stylusFile))  if dirItems[stylusFile] and dirItems[stylusFile].isFile()

      Future.all(modifiedPromises).spread (classModified, templateModified, stylusModified) =>
        if classModified or templateModified or stylusModified
          buildManager.createTask "#{widgetDir}/#{widgetClassFile}", @params.baseDir, @params.targetDir,
            isVdom: true
            classModified: classModified
            templateModified: templateModified
            stylusExists: stylusModified?
            stylusModified: stylusModified
            lastDirName: lowerName


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
    Future.all [
      Future.call(fs.stat, srcPath)
      Future.call(fs.stat, dstPath)
    ]
    .spread (srcStat, dstStat) ->
      srcStat.mtime.getTime() > dstStat.mtime.getTime()
    .catch ->
      true



isVdomWidget = (file) ->
  ###
  Detects if the given file belongs to the virtual-dom widget.
  If it is - returns directory listing of the widget
  @param {string} file - path to the checked file
  @return {Promise.<Object|undefined>}
  ###
  widgetDir = path.dirname(file)
  lowerName = path.basename(widgetDir)
  fsUtils.getDirLsStat(widgetDir).then (dirItems) =>
    vdomTemplateFile = lowerName + '.vdom.html'
    if dirItems[vdomTemplateFile] and dirItems[vdomTemplateFile].isFile()
      dirItems
    else
      undefined



module.exports = BuildSession
