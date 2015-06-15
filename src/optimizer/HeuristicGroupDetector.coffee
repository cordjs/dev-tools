_ = require 'underscore'

sha1 = require 'sha1'


class HeuristicGroupDetector

  constructor: (@groupRepo) ->
    # nothing


  process: (stat) ->
    ###
    Heuristic algorithm is based on iteratively finding of best pairs of modules using sorted by usage frequency
     module list. Loop is interrupted when the best intersection rate is less then 0.2.

    @param {Object<String, Array<String>>} stat
    @return {Object<String, Array<String>>} modified stat with modules replaced by their respective groups.
    ###
    curStat = stat
    while true
      pagesByModule = invertStatMap(curStat)
      countMap = getCountMap(pagesByModule)

      # preparing list of modules sorted by their usage frequency
      sortedModuleList = Object.keys(countMap)
      sortedModuleList = _.sortBy(sortedModuleList, (m) => countMap[m])

      break if sortedModuleList.length < 2

      # finding best intersection between neighbour (by frequency) module pairs
      maxRank = 0
      pair = undefined
      for i in [0..sortedModuleList.length-2]
        m1 = sortedModuleList[i]
        m2 = sortedModuleList[i+1]
        pages1 = pagesByModule[m1]
        pages2 = pagesByModule[m2]
        rank = _.intersection(pages1, pages2).length / pages2.length
        if rank > maxRank
          maxRank = rank
          pair = [m1, m2]

      break if maxRank < 0.2 # best intersection is too bad, giving up

      bestGroup = @groupRepo.createGroup(generateGroupId(pair), pair)

      # rebuilding stat map according to the newly created group
      optimizedStat = {}
      for page, moduleList of curStat
        # replacing modules from the found pairs with the newly created group
        modules = _.clone(moduleList)
        lengthBefore = modules.length
        modules = _.difference(modules, bestGroup.getItems())
        # if the newly created group is big enough, then excluding it from the stat
        # (avoiding result of one huge group including all modules)
        if lengthBefore > modules.length and bestGroup.getModules().length < 20
          modules.push(bestGroup.id)
        optimizedStat[page] = modules

      curStat = optimizedStat

    curStat



generateGroupId = (items) ->
  itemsStr = items.sort().join()
  'group-heuristic-' + sha1(itemsStr) + '-' + items.length + '-' + itemsStr.substr(-12)


invertStatMap = (stat) ->
  ###
  Inverts stat map from `pageName -> Array<moduleName>` to `moduleName -> Array<pageName>`
  @param {Object<String, Array<String>>} stat
  @return {Object<String, Array<String>>}
  ###
  result = {}
  for page, moduleList of stat
    for module in moduleList
      if module.indexOf('/bundles/cord/core/init/browser-init.js') == -1
        result[module] ?= []
        result[module].push(page)
  result


getCountMap = (pagesByModule) ->
  result = {}
  for module, pages of pagesByModule
    result[module] = pages.length
  result


module.exports = HeuristicGroupDetector
