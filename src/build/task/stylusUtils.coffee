fs     = require 'fs-ext'
mkdirp = require 'mkdirp'
path   = require 'path'
_      = require 'underscore'

stylus = require 'stylus'
nib = require 'nib'

fsUtils = require '../../utils/fsUtils'
Future = require '../../utils/Future'

coreUtils = require './coreUtils'


replaceImportsRe = /^@import\s+['"](.+)['"]\s*$/gm
replaceRequiresRe = /^@require\s+['"](.+)['"]\s*$/gm


exports.importStylusLibs = (style) ->
  ###
  Stylus plugin that sets up common slylus libraries used in the project
  ###
  style.define('url', stylus.url())
  style.use(nib())
  style.import('nib')


exports.preprocessWidgetStylus = (stylusStr, filePath, targetDir) ->
  ###
  Recursively scans the given stylus code for @import and @require directives.
  This function is specific for widget's main stylus file.
  Dependencies are also recursively preprocessed and saved in target dir with replaced paths.
  For @import-directives cord-style paths are replaced with resolved paths.
  @require-directives are removed from the result code and listed separately in result.
  @param {string} stylusStr - source stylus code
  @param {string} filePath - the corresponding stylus-file path (needed to detect bundle)
  @return {Promise.<Tuple.<string, Array.<string>>>} preprocessed stylus code and list of dependencies
  ###
  promises = []

  # @imports are treated as usual stylus @import directive
  preprocessedStr = stylusStr.replace replaceImportsRe, (match, p1) ->
    if p1.substr(-4) == '.css'
      throw new Error(
        "Native css @import is not supported in widget's stylus-file, use @require instead! " +
        "Failed for '#{p1}' in '#{filePath}'."
      )
    preprocessedFilePath = normalizeImportStylusPath(p1, filePath, targetDir)
    promises.push(recPreprocessImports(preprocessedFilePath, targetDir))
    "@import '#{preprocessedFilePath}.pre'"

  # @require in widget's stylus file is treated as external requirement handled by the widget (not by stylus compiler)
  deps = []
  preprocessedStr = preprocessedStr.replace replaceRequiresRe, (match, p1) ->
    deps.push(normalizeRequiredCssPath(p1, filePath, targetDir))
    ''

  Future.all(promises).then ->
    [preprocessedStr, deps]


exports.preprocessBundleStylus = (stylusStr, filePath, targetDir) ->
  ###
  Recursively scans the given stylus code for @import directives.
  This function is specific for bundle/root/css directory.
  Dependencies are also recursively preprocessed and saved in target dir with replaced paths.
  For @import-directives cord-style paths are replaced with resolved paths.
  @require-directives are prohibited.
  @param {string} stylusStr - source stylus code
  @param {string} filePath - the corresponding stylus-file path (needed to detect bundle)
  @return {Promise.<string>} preprocessed stylus code
  ###
  promises = []

  # @imports are treated as usual stylus @import directive
  preprocessedStr = stylusStr.replace replaceImportsRe, (match, p1) ->
    if p1.substr(-4) == '.css'
      throw new Error("Native css @import is not supported! Failed for '#{p1}' in '#{filePath}'.")
    preprocessedFilePath = normalizeImportStylusPath(p1, filePath, targetDir)
    promises.push(recPreprocessImports(preprocessedFilePath, targetDir))
    "@import '#{preprocessedFilePath}.pre'"

  # @require directives are not supported in the common bundle-wide stylus files
  if replaceRequiresRe.test(stylusStr)
    throw new Error("@require directive is not supported for the common stylus files! Failed in '#{filePath}'.")

  Future.all(promises).then ->
    preprocessedStr


recPreprocessImports = (src, targetDir) ->
  ###
  Replaces @import paths in the given stylus file and saves the preprocessed version to the targetDir
   with the same relative path.
  Protects against concurrent preprocessing using good-old flock.
  Performs preprocess only in case of the target file is absent or out-of-date.
  @param {string} src - path to the source stylus-file relative to the project base directory
  @param {string} targetDir - absolute path to the projects target root
  @return {Promise.<undefined>} the promise is resolved when preprocessed file is ready to be used as a dependency
  ###
  dst = "#{targetDir}/#{src}.pre.styl"
  src += '.styl'  #if src.substr(-5) != '.styl'
  fsUtils.sourceModified(src, dst).then (modified) ->
    if modified
      Future.call(mkdirp, path.dirname(dst)).then ->
        fd = fs.openSync(dst, 'w')
        Future.call(fs.flock, fd, 'exnb').then ->
          Future.call(fs.readFile, src, 'utf8').then (stylusStr) ->
            if replaceRequiresRe.test(stylusStr)
              throw new Error("@require directive is not supported for the common stylus files, use ")

            promises = []
            preprocessedStr = stylusStr.replace replaceImportsRe, (match, p1) ->
              if p1.substr(-4) == '.css'
                throw new Error("Native css @import is not supported! Failed for '#{p1}' in '#{src}'.")
              preprocessedFilePath = normalizeImportStylusPath(p1, src, targetDir)
              promises.push(recPreprocessImports(preprocessedFilePath, targetDir))  if p1.substr(-4) != '.css'
              "@import '#{preprocessedFilePath}.pre'"
            Future.all [
              Future.all(promises)
              Future.call(fs.write, fd, preprocessedStr)
            ]
          .then ->
            Future.call(fs.flock, fd, 'un')
        .catch (err) ->
          if err.errno == 'EWOULDBLOCK'
            # another process has acquired exclusive lock and we should just wait for it's result.
            Future.call(fs.flock, fd, 'sh').then ->
              Future.call(fs.flock, fd, 'un')
          else
            throw err
        .finally ->
          Future.call(fs.close, fd)
        .then(_.noop)
    else
      return


normalizeImportStylusPath = (importPath, context, targetDir) ->
  ###
  Normalizes the given stylus path - converts from canonical cordjs format to the project-root-relative path.
  Also supported path relative to the given context directory.
  File extension (.styl) is cut off if exists.
  Two subsequent slashes in canonical path is interpreted as `css` directory in bundle root.
  @param {string} importPath - original path from @import directive
  @param {string} context - path to the context stylus file
  @param {string} targetDir - project target root directory used to load core pathUtils
  @return {string} e.g. public/bundles/cord/example/css/common
  ###
  if importPath.indexOf('//') > -1
    pu = coreUtils.pathUtils(targetDir)
    bundle = pu.extractBundleByFilePath(context)
    info = pu.parsePathRaw("#{importPath}@#{bundle}")

    # cut .styl extension if exists
    info.relativePath = info.relativePath.slice(0, -5)  if info.relativePath.substr(-5) == '.styl'

    "public/bundles#{info.bundle}/css/#{info.relativePath}"
  else
    # if path is not canonical then only paths relative to the current directory are allowed
    importPath = importPath.slice(2)  if importPath.substr(0, 2) == './'
    # cut .styl extension if exists
    importPath = importPath.slice(0, -5)  if importPath.substr(-5) == '.styl'

    if importPath.charAt(0) in ['/', '.']
      throw new Error(
        "Css @import must have path relative to current dir or canonical path, '#{importPath}' invalid in #{context}!"
      )
    if importPath.indexOf('../') > -1
      throw new Error(
        "Css @import cannot contain link to parent directory (../)! #{importPath} invalid in #{context}!"
      )
    "#{path.dirname(context)}/#{importPath}"


normalizeRequiredCssPath = (path, context, targetDir) ->
  ###
  Normalizes the given stylus/css path - converts from canonical cordjs format
   to the "absolute" public-root-relative path (URL).
  Also supported absolute path started from '/bundles' and '/vendor'.
  File extension is left untouch.
  Two subsequent slashes in canonical path is interpreted as `css` directory in bundle root.
  @param {string} path - the converted path, e.g. //common
  @param {string} context - context file path to detect the "current" bundle for relative canonical paths
  @param {string} targetDir - project target root directory used to load core pathUtils
  @return {string} e.g. /bundles/cord/example/css/common
  ###
  if path.indexOf('//') > -1
    pu = coreUtils.pathUtils(targetDir)
    bundle = pu.extractBundleByFilePath(context)
    info = pu.parsePathRaw("#{path}@#{bundle}")
    "/bundles#{info.bundle}/css/#{info.relativePath}"
  else
    # absolute paths are left untouch, just checking they are valid
    if path.charAt(0) != '/'
      throw new Error("Css @require should have absolute path or canonical path, '#{path}' invalid!")
    if not (path.split('/')[1] in ['assets', 'vendor'])
      throw new Error(
        "Css @require should be located in 'assets' or 'vendor' root directory in project's 'public'! " +
        "#{path} invalid in #{context}!"
      )
    path
