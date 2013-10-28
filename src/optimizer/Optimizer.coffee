fs = require 'fs'

_      = require 'underscore'
mkdirp = require 'mkdirp'

Future = require '../utils/Future'
sha1   = require '../utils/sha1'

ByWidgetGroupDetector    = require './ByWidgetGroupDetector'
CorrelationGroupDetector = require './CorrelationGroupDetector'
GroupRepo                = require './GroupRepo'
HeuristicGroupDetector   = require './HeuristicGroupDetector'


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

    resultMap


  _mergeGroups: (groupsMap) ->
    result = {}
    for groupId, modules of groupsMap
      result[groupId] = @_mergeGroup(modules)
    result


  _mergeGroup: (modules) ->
    mergedContent = ''
    futures = for module in modules
      do (module) ->
        Future.call(fs.readFile, "target/public/#{module}.js", 'utf8').map (js) ->
          js = js.replace('define(', "define('#{module}',")
          mergedContent += js + "\n\n"
          true
        .mapFail ->
          false
    Future.call(mkdirp, 'target/public/assets/z').zip(Future.sequence(futures)).flatMap ->
      Future.call(fs.writeFile, "target/public/assets/z/#{ sha1(mergedContent) }.js", mergedContent)


module.exports = Optimizer
