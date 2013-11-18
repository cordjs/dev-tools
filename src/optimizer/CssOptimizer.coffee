fs   = require 'fs'
path = require 'path'

_        = require 'underscore'
CleanCss = require 'clean-css'
mkdirp   = require 'mkdirp'

Future = require '../utils/Future'
sha1   = require '../utils/sha1'

CorrelationGroupDetector = require './CorrelationGroupDetector'
GroupRepo                = require './GroupRepo'
HeuristicGroupDetector   = require './HeuristicGroupDetector'


cleanCss = new CleanCss
relativeReplaceRe = /url\(['"]((?!data:|\/|http:\/\/)[^'"]+)['"]\)/gi

class CssOptimizer
  ###
  CSS files optimizer.
  * grouping files into single files
  * minifying, gzipping
  * and so on
  ###

  _zDir: null
  _cleanFuture: null
  _globalOrder: null


  constructor: (@params) ->
    @_zDir = "#{@params.targetDir}/public/assets/z"


  run: ->
    start = process.hrtime()

    cssStatFile = 'css-stat.json'
    fs.readFile cssStatFile, (err, data) =>
      stat = if err then {} else JSON.parse(data)
      @_calculateGlobalOrder(stat)
      console.log "Calculating css group optimization..."
      groupMap = @_generateOptimizationMap(stat)
      @_generateOptimizedFiles(groupMap).done ->
        diff = process.hrtime(start)
        console.log "Optimization complete in #{ (diff[0] * 1e9 + diff[1]) / 1e6 } ms"


  _generateOptimizationMap: (stat) ->
    iterations = 1
    groupRepo = new GroupRepo
    while iterations--
      console.log "100% correlation group detection..."
      corrDetector = new CorrelationGroupDetector(groupRepo)
      stat = corrDetector.process(stat)

      console.log "Heuristic group detection..."
      # heuristic optimization of the previous stage result
      heuristicDetector = new HeuristicGroupDetector(groupRepo)
      stat = heuristicDetector.process(stat)

    resultMap = {}
    for page, groups of stat
      for groupId in groups
        group = groupRepo.getGroup(groupId)
        resultMap[groupId] = _.uniq(group.getModules()) if group

    resultMap


  _generateOptimizedFiles: (groupMap) ->
    ###
    Generates and saves optimized module group and configuration files
    @param Map[String -> Array[String]] groupMap optimized group map
    @return Future
    ###
    console.log "Merging group files..."
    @_mergeGroups(groupMap)
#    .flatMap (mergedMap) =>
#      console.log "Generating browser-init script..."
#      browserInitGenerator.generate(mergedMap, @params)
#    .flatMap (browserInitScriptString) =>
#      fileName = sha1(browserInitScriptString)
#      Future.call(fs.writeFile, "#{@_zDir}/#{fileName}.js", browserInitScriptString)
#        .zip(Future.call(fs.writeFile, "#{@_zDir}/browser-init.id", fileName))


  _mergeGroups: (groupMap) ->
    ###
    Launches merge for all optimized groups.
    Returns converted group map with group names replaced with generated merged file names
    @param Map[String -> Array[String]] groupMap source group map
    @param Object requireConf requirejs configuration object
    @return Future[Map[String -> Array[String]]
    ###
    result = new Future(1)
    resultMap = {}
#    @_cleanFuture = (if @params.clean then rmrf(@_zDir) else Future.resolved()).flatMap =>
    @_cleanFuture = Future.resolved().flatMap =>
      Future.call(mkdirp, @_zDir)
    for groupId, cssFiles of groupMap
      do (cssFiles) =>
        result.fork()
        @_mergeGroup(@_reorderGroupFiles(cssFiles)).done (fileName) ->
          resultMap[fileName] = cssFiles
          result.resolve()
    result.resolve().map -> resultMap


  _mergeGroup: (cssFiles) ->
    ###
    Merges the given modules list into one big optimized file. Order of the modules is preserved.
    Returns future with optimized file name.
    @param Array[String] modules list of group modules
    @param Object requireConf requirejs configuration object
    @return Future[String]
    ###
    contentArr = []
    futures = for file, j in cssFiles
      do (file, j) =>
        filePath = "#{@params.targetDir}/public#{file}"
        Future.call(fs.readFile, filePath, 'utf8').map (origCss) =>
          # replacing relative urls
          fileBaseUrl = path.dirname(file)
          css = origCss.replace(relativeReplaceRe, "url(\"#{fileBaseUrl}/$1\")")

          # header comment for debugging
          css = "/* #{file} */\n\n#{css}\n"

          contentArr[j] = css
          true
        .mapFail ->
          # ignoring absent files (it may be caused by the obsolete stat-file)
          false

    Future.sequence(futures).zip(@_cleanFuture).flatMap =>
      mergedContent = contentArr.join("\n\n")
      mergedContent = cleanCss.minify(mergedContent)
      fileName = sha1(mergedContent)
      console.log "Saving #{fileName}.css ..."
      Future.call(fs.writeFile, "#{@_zDir}/#{fileName}.css", mergedContent).map ->
        fileName
    .failAloud()


  _reorderGroupFiles: (cssFiles) ->
    ###
    Returns ordered css-files according to the pre-computed global order list
    @param Array[String] cssFiles
    @return Array[String]
    ###
    _.sortBy cssFiles, (f) => @_globalOrder.indexOf(f)


  _calculateGlobalOrder: (stat) ->
    ###
    Calculates and saves global order of the css-files based on stats collected from the browser loading order.
    In some cases it's not possible to construct strict order of all files. In those cases approximation is assumed.
    @param Map[String, Array[String]] stat
    ###
    # constructing structure with prepend list (list of files that should be loaded earlier) for each file
    prepends = {}
    for p, files of stat
      for file, i in files
        prepends[file] ?= []
        prepends[file] = prepends[file].concat(files.slice(0, i))

    for file, preps of prepends
      preps = _.uniq(preps)
      prepends[file] =
        files: preps
        size: preps.length

    result = []

    prevLength = Object.keys(prepends).length + 1
    while (keys = Object.keys(prepends)) and keys.length > 0 and keys.length < prevLength
      prevLength = keys.length
      ready = []
      s = 0
      # trying to find files which has not prepends or their prepends are already in the result list
      while ready.length == 0
        ready = _.filter keys, (k) -> prepends[k].size == s
        s++
      # if there was no such files than taking the first random file with the least number of prepends
      ready = [ready[0]] if s > 1
#      ready = [prepends[ready[0]].files[0]] if s > 1
      result = result.concat(ready)
      # removing found file from the base struct and from the prepends of the other files
      delete prepends[k] for k in ready
      for file, preps of prepends
        preps1 = _.difference(preps.files, ready)
        prepends[file] =
          files: preps1
          size: preps1.length

    @_globalOrder = result



module.exports = CssOptimizer
