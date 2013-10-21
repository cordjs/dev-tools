fs = require 'fs'

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
    while iterations--
      # grouping by 100% correlation condition
      corrDetector = new CorrelationGroupDetector(groupRepo)
      stat = corrDetector.process(stat)

      # heuristic optimization of the previous stage result
      heuristicDetector = new HeuristicGroupDetector(groupRepo)
      stat = heuristicDetector.process(stat)

    stat



module.exports = Optimizer
