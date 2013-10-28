path = require 'path'

_ = require  'underscore'

sha1 = require '../utils/sha1'


class ByWidgetGroupDetector
  ###
  Groups all widget's js files together.
  ###

  constructor: (@groupRepo) ->
    # nothing


  process: (stat) ->
    widgetGroups = {}
    widgetsRe = /^bundles\/.+\/widgets\//
    for page, modules of stat
      for module in modules
        if widgetsRe.test(module)
          key = path.dirname(module)
          widgetGroups[key] ?= []
          widgetGroups[key].push(module) if widgetGroups[key].indexOf(module) == -1

    resultGroups = []
    for gr, items of widgetGroups
      if items.length > 1
        resultGroups.push(@groupRepo.createGroup(@_generateGroupId(items, gr), items))

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


  _generateGroupId: (items, groupDir) ->
    itemsStr = items.sort().join()
    'group-widget-' + sha1(itemsStr) + '-' + items.length + '-' + groupDir.substr(-12)



module.exports = ByWidgetGroupDetector
