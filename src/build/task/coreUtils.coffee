path = require 'path'


pathToCore = 'public/bundles/cord/core'

# local cache
cachedPathUtils = null

exports.pathUtils = pathUtils = (targetDir, repeat = 0) ->
  ###
  Loads, caches and returns pathUtils module of the cordjs-core bundle which is used to detect correct file paths
   in several cases.
  Retries 10 times if the module contents is invalid.
  @param {string} targetDir - root of the built project (with compiled js-files)
  @param {number=} repeat - current repeat counter
  @todo retry algoritm correctness is doubtful, nodejs's require caches itself and woldn't retry to load the module
  @return {Object}
  ###
  cachedPathUtils = require("#{targetDir}/#{pathToCore}/requirejs/pathUtils")  if not cachedPathUtils
  if typeof cachedPathUtils.convertCssPath != 'function' and repeat < 10
    path = "#{targetDir}/#{pathToCore}/requirejs/pathUtils.js"
    console.error ''
    console.error '###############################################################'
    console.error "Invalid pathUtils:", cachedPathUtils, cachedPathUtils._publicPrefix, cachedPathUtils.convertCssPath, repeat
    console.error path
    console.error fs.readFileSync(path, encoding: 'utf8')
    console.error '###############################################################'
    console.error ''
    cachedPathUtils = null
    cachedPathUtils = pathUtils(targetDir, repeat + 1)
  cachedPathUtils


exports.getPathToCore = ->
  ###
  Returns relative path to the cord/core bundle from the project's base directory
  @return {string}
  ###
  pathToCore
