fs = require 'fs'

_        = require 'underscore'
mkdirp   = require 'mkdirp'
UglifyJS = require 'uglify-js'

Future = require '../utils/Future'
sha1   = require '../utils/sha1'

ByWidgetGroupDetector    = require './ByWidgetGroupDetector'
CorrelationGroupDetector = require './CorrelationGroupDetector'
GroupRepo                = require './GroupRepo'
HeuristicGroupDetector   = require './HeuristicGroupDetector'


coffeeUtilCode = [
  '__hasProp = {}.hasOwnProperty'
  '__extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; }'
  '__bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; }'
  '__slice = [].slice'
  '__indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; }'
]

class Optimizer

  run: ->
    statFile = 'require-stat.json'
    fs.readFile statFile, (err, data) =>
      stat = if err then {} else JSON.parse(data)
      console.log JSON.stringify(@generateOptimizationMap(stat), null, 2)


  generateOptimizationMap: (stat) ->
    iterations = 1
    groupRepo = new GroupRepo

    widgetDetector = new ByWidgetGroupDetector(groupRepo)
    stat = widgetDetector.process(stat)

    while iterations--
      # grouping by 100% correlation condition
      corrDetector = new CorrelationGroupDetector(groupRepo)
      stat = corrDetector.process(stat)

      # heuristic optimization of the previous stage result
      heuristicDetector = new HeuristicGroupDetector(groupRepo)
      stat = heuristicDetector.process(stat)

    resultMap = {}
    for page, groups of stat
      for groupId in groups
        group = groupRepo.getGroup(groupId)
        resultMap[groupId] = _.uniq(group.getModules()) if group

    @_mergeGroups(resultMap)


  _mergeGroups: (groupsMap) ->
    result = new Future(1)
    resultMap = {}
    for groupId, modules of groupsMap
      do (modules) =>
        result.fork()
        @_mergeGroup(modules).done (fileName) ->
          resultMap[fileName] = modules
          result.resolve()
    result.resolve().map -> resultMap


  _mergeGroup: (modules) ->
    mergedContent = ''
    csUtilHit = {}
    futures = for module in modules
      do (module) ->
        Future.call(fs.readFile, "target/public/#{module}.js", 'utf8').map (js) ->
          js = js.replace('define(', "define('#{module}',")
          for code, i in coffeeUtilCode
            if js.indexOf(code) > -1
              js = js.replace(code + ",\n  ", '')
              js = js.replace(code, '')
              csUtilHit[i] = true
          js = js.replace("var ;\n", '')

          mergedContent += js + "\n\n"
          true
        .mapFail ->
          false
    Future.call(mkdirp, 'target/public/assets/z').zip(Future.sequence(futures)).flatMap ->
      hit = Object.keys(csUtilHit)
      if hit.length > 0
        resultCode = 'var ' + (coffeeUtilCode[i] for i in hit).join(',\n  ') + ';\n\n'
        mergedContent = resultCode + mergedContent

#      mergedContent = UglifyJS.minify(mergedContent, fromString: true).code

      fileName = sha1(mergedContent)

      Future.call(fs.writeFile, "target/public/assets/z/#{ fileName }.js", mergedContent).map ->
        fileName


module.exports = Optimizer
