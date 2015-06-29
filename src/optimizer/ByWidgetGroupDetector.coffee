fs   = require 'fs'
path = require 'path'

_ = require  'underscore'

Future    = require '../utils/Future'
sha1      = require 'sha1'
appConfig = require '../appConfig'


class ByWidgetGroupDetector
  ###
  Groups all widget's js files together.
  ###

  _widgetGroups: null

  constructor: (@groupRepo, @targetDir) ->
    @_widgetGroups = {}
    # nothing


  _processDir: (target) ->
    ###
    Recursively scans the given directory to group widgets files together.
    @param String target absolute path to the file/directory to be removed
    @return {Future<undefined>}
    ###
    Future.call(fs.stat, target).then (stat) =>
      if stat.isDirectory()
        @_widgetGroups[target.substr(target.indexOf('/bundles/') + 1)] = []
        Future.call(fs.readdir, target).then (items) =>
          futures = (@_processDir(path.join(target, item)) for item in items)
          Future.all(futures)
        .then(_.noop)
      else if path.extname(target) == '.js'
        moduleName = target.slice(target.indexOf('/bundles/') + 1, -3)
        key = path.dirname(moduleName)
        @_widgetGroups[key].push(moduleName)
        Future.resolved()
      else
        Future.resolved()


  process: (stat) ->
    appConfig.getBundles(@targetDir).then (bundles) =>
      futures = for bundle in bundles
        @_processDir(path.join(@targetDir, 'public/bundles', bundle, 'widgets'))
          .catchIf (err) -> err.code == 'ENOENT' # the bundle may not have 'widgets' folder
      Future.all(futures)
    .then =>
      resultGroups = []
      for gr, items of @_widgetGroups
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
    .failAloud('ByWidgetGroupDetector::processing')


  _generateGroupId: (items, groupDir) ->
    itemsStr = items.sort().join()
    'group-widget-' + sha1(itemsStr) + '-' + items.length + '-' + groupDir.substr(-12)



module.exports = ByWidgetGroupDetector
