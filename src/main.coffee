_ = require 'underscore'

Future = require './utils/Future'
rmrf   = require './utils/rmrf'
normalizePathSeparator = require './utils/fsNormalizePathSeparator'

cliParser            = require './cli-parser'
Optimizer            = require './optimizer/Optimizer'
purgeSources         = require './optimizer/purgeSources'
ProjectBuilder       = require './build/ProjectBuilder'
ServerProcessManager = require './server/ServerProcessManager'


exports.main = ->
  ###
  Main cordjs CLI tool entry point.
  ###
  commands =
    build: (options) ->
      ###
      Builds whole project.
      ###
      handleChdir(options)
      buildOptions = normalizeBuildOptions(options)
      buildOptions.config = options.config
      cleanFuture = if buildOptions.clean then commands.clean(options) else Future.resolved()
      cleanFuture.then ->
        builder = new ProjectBuilder(buildOptions)
        builder.build().fail ->
          process.exit(1) if not buildOptions.watch
        [builder, buildOptions]
      .failAloud()


    buildIndex: (options) ->
      ###
      Builds only index.html file.
      ###
      handleChdir(options)
      buildOptions = normalizeBuildOptions(options)
      buildOptions.config = options.config

      builder = new ProjectBuilder(buildOptions)
      builder.buildIndex()
      return


    run: (options) ->
      ###
      Builds project and starts cordjs server
      ###
      commands.build(options).spread (builder, buildOptions) ->
        serverOptions = normalizeServerOptions(options)
        serverProcessManager = new ServerProcessManager(_.extend(buildOptions, serverOptions))
        builder.on 'complete', ->
          console.log 'Restarting...'
          console.log '---------------------'
          serverProcessManager.restart()
      .failAloud()


    optimize: (options) ->
      handleChdir(options)
      optimizer = new Optimizer
        targetDir: "#{ normalizePathSeparator(process.cwd()) }/#{ options.out }"
        clean: options.clean
        css: not options.disableCss
        cssMinify: not options.disableCssMinify
        js: not options.disableJs
        jsMinify: not options.disableJsMinify
        removeSources: !!options.removeSources
      optimizer.run()


    purgeOptimizedSources: (options) ->
      handleChdir(options)
      purgeSources("#{ preparePath(process.cwd()) }/#{ options.out }")



    clean: (options) ->
      console.log "Cleaning project..."
      handleChdir(options)
      rmrf(normalizeBuildOptions(options).targetDir)


  cliParser.run(commands)



handleChdir = (options) ->
  process.chdir(options.parent.chdir) if options.parent.chdir


normalizeBuildOptions = (options) ->
  curDir = normalizePathSeparator(process.cwd())

  baseDir: curDir
  targetDir: "#{curDir}/#{ if options.out then options.out else 'target'}"
  watch: !!options.watch
  clean: !!options.clean
  map: !!options.map
  appConfigName: "#{ if options.app then options.app else 'application'}"
  indexPageWidget: options.index


normalizeServerOptions = (options) ->
  config: options.config
  port: parseInt(options.port)
  map: !!options.map
