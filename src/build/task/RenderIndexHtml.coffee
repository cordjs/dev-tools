fs   = require 'fs'
path = require 'path'

requirejs = require process.cwd() + '/node_modules/requirejs'

Future = require '../../utils/Future'

BuildTask       = require './BuildTask'
coreUtils       = require './coreUtils'
requirejsConfig = require './requirejs-config'


class RenderIndexHtml extends BuildTask
  ###
  Renders and saves given widget (came from -I --index CLI option) as main index.html page.
  This is need mainly for mobile apps (phonegap) working in SPA mode.
  ###

  run: ->
    dst = "#{@params.targetDir}/public/index.html"

    # loading CordJS configuration
    nodeInit = require(path.join(@params.targetDir, coreUtils.getPathToCore(), 'init/nodeInit'))
    config = nodeInit.loadConfig(@params.info.configName)

    global.appConfig = config
    global.config    = config.node
    global.CORD_PROFILER_ENABLED = config.node.debug.profiler.enable

    browserInitPromise =
      Future.call(fs.readFile, path.join(@params.targetDir, 'public/assets/z/browser-init.id'), 'utf8').then (id) ->
        global.config.browserInitScriptId = id
        return
      .catch -> return

    Future.all [
      browserInitPromise
      requirejsConfig(@params.targetDir)
    ]
    .then ->
      Future.require(
        'cord!AppConfigLoader'
        'cord!utils/DomInfo'
        'cord!ServiceContainer'
        'cord!router/serverSideRouter'
      )
    .spread (AppConfigLoader, DomInfo, ServiceContainer, ServerSideRouter) =>
      # replace placeholder in configs
      config = ServerSideRouter.constructor.replaceConfigVarsByHost(config, '127.0.0.1', 'http')

      global.appConfig = config
      global.config    = config.node

      # initializing core CordJS services
      serviceContainer = new ServiceContainer
      serviceContainer.set('serviceContainer', serviceContainer)
      serviceContainer.set('config', global.config)
      serviceContainer.set('appConfig', global.appConfig)

      AppConfigLoader.ready().then (appConfig) =>
        appConfig.services.cookie =
          deps: ['serviceContainer']
          factory: (get, done) ->
            requirejs ['cord!/cord/core/cookie/LocalCookie'], (Cookie) =>
              done(null, new Cookie(get('serviceContainer')))

        for serviceName, info of appConfig.services
          do (info) ->
            serviceContainer.def serviceName, info.deps, (get, done) ->
              info.factory.call(serviceContainer, get, done)

        serviceContainer.getService('widgetRepo').then (widgetRepo) =>
          # rendering the given widget to save as index.html
          widgetRepo.createWidget(@params.file).then (rootWidget) ->
            rootWidget._isExtended = true
            widgetRepo.setRootWidget(rootWidget)
            rootWidget.show({}, DomInfo.fake())
    .then (out) ->
      Future.call(fs.writeFile, dst, out)
    .link(@readyPromise)


module.exports = RenderIndexHtml
