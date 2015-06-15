_ = require  'underscore'

sha1 = require 'sha1'


class CorrelationGroupDetector
  ###
  Optimizer that finds out groups of modules which are always used together (100% correlation)
  ###

  constructor: (@groupRepo) ->
    # nothing


  process: (stat) ->
    # the idea is to group together modules based on list of pages in which they are used
    # modules have 100% correlation if they are used in the exactly same list of pages
    checksums = {}
    for module, pages of @_mapStat(stat)
      checksum = @_calculatePagesChecksum(pages)
      checksums[checksum] ?= []
      checksums[checksum].push(module)

    # registering groups in repository and
    # dropping out groups containing only one module
    filteredGroups = {}
    for groupId, modules of checksums when modules.length > 1
      @groupRepo.createGroup(groupId, modules)
      filteredGroups[groupId] = modules

    # preparing new stat array with modules replaced with corresponding groups for futher processing
    optimizedStat = {}
    for page, moduleList of stat
      modules = _.clone(moduleList)
      for checksum, groupModules of filteredGroups
        if modules.indexOf(groupModules[0]) > -1
          modules = _.difference(modules, groupModules)
          modules.push(checksum)  if groupModules.length < 20
      optimizedStat[page] = modules

    optimizedStat


  _calculatePagesChecksum: (pages) ->
    ###
    Returns unique id based on list of pages in which the module is used.
    @param Array[String] pages list of pages root widgets names
    @return String
    ###
    pagesStr = pages.sort().join()
    'group-correlation-' + sha1(pagesStr) + '-' + pages.length + '-' + pagesStr.substr(-10)


  _mapStat: (stat) ->
    result = {}
    for page, moduleList of stat
      for module in moduleList
        if module.indexOf('/bundles/cord/core/init/browser-init.js') == -1
          result[module] ?= []
          result[module].push(page)
    result



module.exports = CorrelationGroupDetector
