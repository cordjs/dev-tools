fs = require 'fs'

_        = require 'underscore'
UglifyJS = require 'uglify-js'

Future = require '../utils/Future'
sha1   = require '../utils/sha1'

ByWidgetGroupDetector    = require './ByWidgetGroupDetector'
CorrelationGroupDetector = require './CorrelationGroupDetector'
GroupRepo                = require './GroupRepo'
HeuristicGroupDetector   = require './HeuristicGroupDetector'
requirejsConfig          = require './requirejsConfig'


coffeeUtilCode = [
  '__hasProp = {}.hasOwnProperty'
  '__extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; }'
  '__bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; }'
  '__slice = [].slice'
  '__indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; }'
]


class JsOptimizer
  ###
  Build optimizer.
  * grouping modules into single files
  * minifying, gzipping
  * and so on
  ###

  _zDir: null
  _requireConfig: null


  constructor: (@params, @zDirFuture) ->
    @_zDir = "#{@params.targetDir}/public/assets/z"


  run: ->
    # will need it later
    @_requireConfig = requirejsConfig.collect(@params.targetDir)

    statFile = 'require-stat.json'
    statPromise = Future.call(fs.readFile, statFile).catch ->
      console.warn "Error reading require-stat file '#{statFile}'. Going to group only by widget..."
      '{}'
    .then (data) =>
      JSON.parse(data)

    predefinedPromise = Future.require("#{@params.targetDir}/optimizer-predefined-groups").catch (err) ->
      console.warn "Error reading predefined-groups file: #{err}!"
      {}

    Future.all([statPromise, predefinedPromise]).spread (stat, predefinedGroupsInfo) =>
      console.log "Calculating JS group optimization..."
      @_generateOptimizationMap(stat, predefinedGroupsInfo)
    .then (groupMap) =>
      @_generateOptimizedFiles(groupMap)
    .catch (e) ->
      console.warn "JS group optimization failed! Reason: #{ e }. Skipping...", e.stack
      {}


  _generateOptimizationMap: (stat, predefinedGroupsInfo) ->
    ###
    Analizes collected requirejs stats and tryes to group modules together in optimized way.
    @param Map[String -> Array[String]] stat collected statistics of required files per page
    @return Map[String -> Array[String]]
    ###
    iterations = 1
    groupRepo = new GroupRepo

    @_createPredefinedGroups(predefinedGroupsInfo, groupRepo)
    @_removePredefinedGroupsFromStat(stat, predefinedGroupsInfo)
    @_removeBrowserInitFromStat(stat)

    widgetDetector = new ByWidgetGroupDetector(groupRepo, @params.targetDir)
    widgetDetector.process(stat).then (stat) ->
      while iterations--
        console.log "100% correlation JS group detection..."
        corrDetector = new CorrelationGroupDetector(groupRepo)
        stat = corrDetector.process(stat)

        console.log "Heuristic JS group detection..."
        # heuristic optimization of the previous stage result
        heuristicDetector = new HeuristicGroupDetector(groupRepo)
        stat = heuristicDetector.process(stat)

      resultMap = {}
      for page, groups of stat
        for groupId in groups
          group = groupRepo.getGroup(groupId)
          resultMap[groupId] = _.uniq(group.getModules()) if group
          groupRepo.removeGroupDeep(groupId) if group

      # adding unused widget groups to the result map
      for groupId, group of groupRepo.getGroups() when not group.isSubGroup()
        resultMap[groupId] = _.uniq(group.getModules())

      resultMap


  _createPredefinedGroups: (predefinedGroupsInfo, groupRepo) ->
    ###
    Registers predefined groups in group repository
    ###
    for name, modules of predefinedGroupsInfo
      groupId = 'predefined-' + sha1(modules.sort().join()) + '-' + name
      groupRepo.createGroup(groupId, modules)
    return


  _removePredefinedGroupsFromStat: (stat, predefinedGroupsInfo) ->
    ###
    Removes modules of predefined groups from the stat to avoid mixing them up with another groups
    ###
    removeModules = []
    for name, modules of predefinedGroupsInfo
      removeModules.push(m) for m in modules
    for page, modules of stat
      stat[page] = _.difference(modules, removeModules)
    return


  _removeBrowserInitFromStat: (stat) ->
    ###
    Removes browser-init script occurences from stat as it never included in any group
    ###
    for page, modules of stat
      modules.shift() if modules[0].indexOf('bundles/cord/core/init/browser-init') != -1
    return


  _generateOptimizedFiles: (groupMap) ->
    ###
    Generates and saves optimized module group and configuration files
    @param Map[String -> Array[String]] groupMap optimized group map
    @return Future
    ###
    @_requireConfig.then (requireConf) =>
      console.log "Merging JS group files..."
      @_mergeGroups(groupMap, requireConf)


  _mergeGroups: (groupMap, requireConf) ->
    ###
    Launches merge for all optimized groups.
    Returns converted group map with group names replaced with generated merged file names
    @param Map[String -> Array[String]] groupMap source group map
    @param Object requireConf requirejs configuration object
    @return Future[Map[String -> Array[String]]
    ###
    resultMap = {}
    mergePromises =
      for groupId, modules of groupMap
        # non-amd modules must be reordered according to their dependencies to work properly in merged file
        @_mergeGroup(@_reorderShimModules(modules, requireConf.shim), requireConf).spread (fileName, existingModules) ->
          resultMap[fileName] = existingModules
          return
    Future.all(mergePromises).then -> resultMap


  _mergeGroup: (modules, requireConf) ->
    ###
    Merges the given modules list into one big optimized file. Order of the modules is preserved.
    Returns future with optimized file name.
    @param Array[String] modules list of group modules
    @param Object requireConf requirejs configuration object
    @return Future[String]
    ###
    existingModules = []
    contentArr = []
    csUtilHit = {}
    removePromises = []
    futures = for module, j in modules
      do (module, j) =>
        moduleFile = if requireConf.paths[module]
          "#{@params.targetDir}/public/#{requireConf.paths[module]}.js"
        else
          "#{@params.targetDir}/public/#{module}.js"
        Future.call(fs.readFile, moduleFile, 'utf8').then (origJs) =>
          removePromises.push(Future.call(fs.unlink, moduleFile))  if @params.removeSources
          # inserting module name into amd module definitions
          js = origJs
            .replace('define([', "define('#{module}',[")
            .replace('define( [', "define('#{module}',[")
            .replace('define(function()', "define('#{module}',function()")
          definePresent = js != origJs or js.indexOf('define.amd') > -1

          # cutting off duplicate coffee-script utility functions definitions
          for code, i in coffeeUtilCode
            if js.indexOf(code) > -1
              js = js.replace(code + ",\n  ", '')
              js = js.replace(code, '')
              csUtilHit[i] = true
          js = js.replace("var ;\n", '')

          # adding fake module definition for non-amd module
          if (shim = requireConf.shim[module]) and shim.exports? and _.isString(shim.exports)
            deps = if _.isArray(shim.deps) and shim.deps.length > 0 then "['#{ shim.deps.join("','") }'], " else ''
            js += "\ndefine('#{module}', #{deps}#{ @_generateShimExportsFn(shim) });\n"
          else if not definePresent
            # even without shim configuration
            js += "\ndefine('#{module}', function(){});\n"

          contentArr[j] = js
          existingModules.push(module)
          true
        .catch ->
          # ignoring absent files (it may be caused by the obsolete stat-file)
          false

    savePromise = Future.all([Future.all(futures), @zDirFuture]).then =>
      resultCode = ''

      # adding one instance of coffee-script utility functions cutted above
      hit = Object.keys(csUtilHit)
      if hit.length > 0
        resultCode += 'var ' + (coffeeUtilCode[i] for i in hit).join(',\n  ') + ';\n\n'

      mergedContent = resultCode + contentArr.join("\n\n")
      if @params.jsMinify
        mergedContent = UglifyJS.minify mergedContent,
          fromString: true
          mangle: true
        .code
      fileName = sha1(mergedContent)
      console.log "Saving #{fileName}.js ..."
      Future.call(fs.writeFile, "#{@_zDir}/#{ fileName }.js", mergedContent).then ->
        [fileName, existingModules]

    Future.all [
      savePromise
      Future.all(removePromises)
    ]
    .spread (savePromiseResult) ->
      savePromiseResult
    .failAloud('JsOptimizer::_mergeGroup')


  _generateShimExportsFn: (shimConfig) ->
    ###
    Generates special function code for shim-module definition. Stolen from the requirejs sources.
    @param Object shimConfig shim configuration for the module
    @return String
    ###
    `'(function (global) {\n' +
    '    return function () {\n' +
    '        var ret, fn;\n' +
    (shimConfig.init ?
            ('       fn = ' + shimConfig.init.toString() + ';\n' +
            '        ret = fn.apply(global, arguments);\n') : '') +
    (shimConfig.exports ?
            '        return ret || global.' + shimConfig.exports + ';\n' :
            '        return ret;\n') +
    '    };\n' +
    '}(this))'`


  _reorderShimModules: (modules, requirejsShim) ->
    ###
    Reorders the given list of modules according to their dependency tree from the shim configuration.
    Order of modules that are not present in shim configuration is leaved untouch. Shim modules are placed in the end.
    In the result array the module A which depends on module B comes after module B.
    @param Array[String] modules source module list
    @param Object requirejsShim shim configuration part of requirejs configuration config object
    @return Array[String]
    ###
    orderInfo = {}
    for module, info of requirejsShim
      if info.deps? and info.deps.length > 0
        orderInfo[module] = {}
        for depModule in info.deps
          if requirejsShim[depModule]?
            orderInfo[module][depModule] = false
          else
            orderInfo[depModule] = 0
            orderInfo[module][depModule] = false
      else
        orderInfo[module] = 0
    while true
      orderUnresolved = false
      for module, deps of orderInfo
        if _.isObject(deps)
          unresolved = false
          for depModule, depInfo of deps
            if depInfo == false
              if not _.isObject(orderInfo[depModule])
                deps[depModule] = orderInfo[depModule] + 1
              else
                unresolved = true
          if not unresolved
            max = 0
            for depModule, depOrder of deps
              max = depOrder if depOrder > max
            orderInfo[module] = max
          else
            orderUnresolved = true
      break if not orderUnresolved

    shimModules = {}
    resultModules = []
    for module in modules
      if orderInfo[module]?
        shimModules[orderInfo[module]] ?= []
        shimModules[orderInfo[module]].push(module)
      else
        resultModules.push(module)
    if Object.keys(shimModules).length > 0
      for i in [0.._.max(Object.keys(shimModules))]
        resultModules = resultModules.concat(shimModules[i]) if shimModules[i]?

    resultModules



module.exports = JsOptimizer
