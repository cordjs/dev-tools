path = require('path')


class FileInfo
  ###
  @static
  ###

  @baseDir: null
  @targetDir: null
  @bundleTree: {}


  @setDirs: (base, target) ->
    @baseDir = base
    @targetDir = target


  @setBundles: (bundles) ->
    ###
    Registers bundle list from the application configuration to be able to detect bundle by the given file path
    @param Array[String] bundles
    ###
    for bundle in bundles
      parts = bundle.split('/')
      last = parts.length - 1
      curLevel = @bundleTree
      for part, i in parts
        if not curLevel[part]?
          curLevel[part] = if i == last then true else {}
        curLevel = curLevel[part]


  @getTargetForSource: (srcAbsPath) ->
    ###
    Returns absolute target file path for the given absolute source file path.
    @param String srcAbsPath
    @return String
    ###
    relativePath = srcAbsPath.substr(@baseDir.length + 1)
    info = @getFileInfo(relativePath, @detectBundle(relativePath))
    path.join(@targetDir, @getBuildDestinationFile(relativePath, info))


  @detectBundle: (file) ->
    ###
    Returns bundle name for the given relative file path.
    @param String file relative (to the base dir) file path
    @return String
    ###
    parts = file.split(path.sep)
    bundles = parts.shift()
    bundles = parts.shift()
    if bundles == 'bundles'
      curLevel = @bundleTree
      result = []
      for ns in parts
        if curLevel[ns]?
          result.push(ns)
          if curLevel[ns] == true
            break
          else
            curLevel = curLevel[ns]
        else
          result = []
          break
      result.join('/')
    else
      ''

  @getFileInfo: (file, bundle) ->
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
          else if inModels
            isModelRepo = ext == '.coffee' and fileWithoutExt.substr(-4) == 'Repo'
            isCollection = ext == '.coffee' and fileWithoutExt.substr(-10) == 'Collection'
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
    isModelRepo: isModelRepo ? false
    isCollection: isCollection ? false
    isCoffee: ext == '.coffee'
    isHtml: ext == '.html'
    isStylus: ext == '.styl'
    isTestSpec: parts[0] == 'test' and parts[parts.length-1] == 'specs' and ext == '.coffee'


  @getBuildDestinationFile: (file, info) ->
    ###
    Returns destination file relative name based on source file and framework-related information
    @param String file relative file name
    @param Object info framework-related information about the file
    @return String
    ###
    if info.isCoffee
      path.dirname(file) + path.sep + info.fileNameWithoutExt + '.js'
    else if info.isStylus
      path.dirname(file) + path.sep + info.fileNameWithoutExt + '.css'
    else if info.isWidgetTemplate
      file + '.js'
    else
      file



module.exports = FileInfo
