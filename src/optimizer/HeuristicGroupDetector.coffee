_ = require 'underscore'

sha1 = require '../utils/sha1'


class HeuristicGroupDetector

  _countMap: null
  _curStat: null
  _maxGroupScore: 0
  # time-point until which computation should continue.
  # When it's reached we just take the best result achieved at that moment
  _thresholdTime: 0


  constructor: (@groupRepo) ->
    # nothing


  process: (stat) ->
    @_countMap = {}
    for module, pages of @_mapStat(stat)
      @_countMap[module] = pages.length

    # converting module arrays to key-value object to optimize detection of group existence (see @_groupExists)
    @_curStat = {}
    for page, moduleList of stat
      @_curStat[page] = {}
      for module in moduleList
        @_curStat[page][module] = true

    remaining = Object.keys(@_countMap)
    # reverse-sorting of items based on their usage frequency
    # should help to find better group within limited amount of time
    remaining = (_.sortBy remaining, (m) => @_countMap[m]).reverse()

    resultGroups = []
    while true
      group = @_findBestGroup(remaining)
      if group != false
        remaining = _.difference(remaining, group.getItems())
        remaining = (_.sortBy remaining, (m) => @_countMap[m]).reverse()
        resultGroups.push(group)

        # removing modules of the found group from the stat-array to narrow down next iteration work
        for page, moduleMap of @_curStat
          @_curStat[page] = _.omit(moduleMap, group.getItems())
          if Object.keys(@_curStat[page]).length == 0
            delete @_curStat[page]
      else
        break

    optimizedStat = {}
    for page, moduleList of stat
      modules = _.clone(moduleList)
      for group in resultGroups
        lengthBefore = modules.length
        modules = _.difference(modules, group.getItems())
        if lengthBefore > modules.length
          modules.push(group.id)
      optimizedStat[page] = modules

    optimizedStat


  _findBestGroup: (moduleList) ->
    groups = []
    console.log "findBestGroup --> ", moduleList.length, (new Date).getTime()
    @_maxGroupScore = 0
    @_thresholdTime = (new Date).getTime() + 120000
    for item, i in moduleList
      groups = groups.concat(@_collectGroups([], moduleList, i, Object.keys(@_curStat), 0))
      break if (new Date).getTime() >= @_thresholdTime
    if groups.length > 0
      _.sortBy(groups, (item) -> item[1]).reverse()
      @groupRepo.createGroup(@_generateGroupId(groups[0][2]), groups[0][2])
    else
      false


  _collectGroups: (prevGroup, list, startIndex, checkPages, level) ->
    ###
    Recursive module group collector
    @param Array[String] prevGroup  accumulated on previous level existing group
    @param Array[String] list       source list of modules to process
    @param Int           startIndex which item of the list to start from (every recursive call must increase it)
    @param Array[String] checkPages short-list of pages to be used to check group existence (shortened by previous level)
    @param Int           level      nesting level for debugging
    @return Array[Array[(Int, Int, Array[String])]]
    ###
    result = []
    if (new Date).getTime() < @_thresholdTime
      for i in [startIndex..list.length]
        [cnt, matchPages] = @_groupExists(list[i], checkPages)
        if cnt > 0
          group = prevGroup.concat([list[i]])

          # calculating score in a little complicated way
          # score is related to the group match count and size of the group, but when calculating size we take into
          # account only those modules whose individual occurences (in different pages) count is not far from
          # the weighted average module occurences count of the group
          scoreArr = _.map group, (m) => [m, @_countMap[m]]
          summ = _.reduce scoreArr, ((res, item) -> res + item[1]), 0
          avg = summ / group.length
          index = _.reduce scoreArr, (res, item) ->
            deviation = Math.abs(item[1] - avg)
            if deviation < res[0]
              [deviation, item[1]]
            else
              res
          , [2000000000, 0]
          scoreArr = _.filter scoreArr, (item) -> Math.abs(item[1] - index[1]) <= 1
          score = cnt * scoreArr.length
          # simple way: score = cnt * group.length

          if score > @_maxGroupScore and group.length > 1 # ignoring single-item groups
            result.push([cnt, score, group])
            @_maxGroupScore = score
            @_thresholdTime = (new Date).getTime() + 30000 # moving threshold ahead
            console.log "maxScore = ", score, group.length, (new Date).getTime()
          result = result.concat(@_collectGroups(group, list, i + 1, matchPages, level + 1))
    result


  _groupExists: (checkModule, checkPages) ->
    ###
    Returns count of pages in which the given module is used.
    @param String checkModule module to check
    @param Array[String] checkPages list of pages to check
    @return Int
    ###
    count = 0
    matchPages = []
    for page in checkPages
      if @_curStat[page][checkModule]
        count++
        matchPages.push(page)
    [count, matchPages]


  _mapStat: (stat) ->
    result = {}
    for page, moduleList of stat
      for module in moduleList
        if module.indexOf('/bundles/cord/core/browserInit.js') == -1
          result[module] ?= []
          result[module].push(page)
    result


  _generateGroupId: (items) ->
    itemsStr = items.sort().join()
    'group-heuristic-' + sha1(itemsStr) + '-' + items.length + '-' + itemsStr.substr(-12)



module.exports = HeuristicGroupDetector
