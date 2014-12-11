fs   = require 'fs'
path = require 'path'
requirejs = require 'requirejs'

Future = require '../../utils/Future'

BuildTask       = require './BuildTask'
requirejsConfig = require './requirejs-config'

pathToCore = 'bundles/cord/core'


class RenderIndexHtml extends BuildTask
  ###
  Renders and saves given widget (came from -I --index CLI option) as main index.html page.
  This is need mainly for mobile apps (phonegap) working in SPA mode.
  ###

  run: ->
    dst = "#{@params.targetDir}/public/index.html"

    # loading CordJS configuration
    nodeInit = require(path.join(@params.targetDir, 'public', pathToCore, 'init/nodeInit'))
    config = nodeInit.loadConfig(@params.info.configName)
    global.appConfig = config
    global.config    = config.node
    global.CORD_PROFILER_ENABLED = config.node.debug.profiler.enable

    Future.call(fs.readFile, path.join(@params.targetDir, 'public/assets/z/browser-init.id'), 'utf8').then (id) ->
      global.config.browserInitScriptId = id
    .catch ->
      true
    .zip(requirejsConfig(@params.targetDir)).then ->
      Future.require('cord!AppConfigLoader', 'cord!utils/DomInfo', 'cord!ServiceContainer', 'cord!WidgetRepo')
    .then (AppConfigLoader, DomInfo, ServiceContainer, WidgetRepo) =>
      # initializing core CordJS services
      container = new ServiceContainer
      container.set('container', container)
      container.set('config', {})
      container.set('appConfig', {})
      widgetRepo = new WidgetRepo
      widgetRepo.setServiceContainer(container)

      AppConfigLoader.ready().then (appConfig) =>
        appConfig.services.cookie =
          deps: ['container']
          factory: (get, done) ->
            requirejs ['cord!/cord/core/cookie/LocalCookie'], (Cookie) =>
              done(null, new Cookie(get('container')))

        for serviceName, info of appConfig.services
          do (info) ->
            container.def serviceName, info.deps, (get, done) ->
              info.factory.call(container, get, done)

        # rendering the given widget to save as index.html
        widgetRepo.createWidget(@params.file).then (rootWidget) ->
          rootWidget._isExtended = true
          widgetRepo.setRootWidget(rootWidget)
          rootWidget.show({}, DomInfo.fake())
    .then (out) ->
      Future.call(fs.writeFile, dst, out)
    .link(@readyPromise)



module.exports = RenderIndexHtml
