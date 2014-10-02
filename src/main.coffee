_ = require 'underscore'

Future = require './utils/Future'
rmrf   = require './utils/rmrf'

cliParser            = require './cli-parser'
Optimizer            = require './optimizer/Optimizer'
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


    run: (options) ->
      ###
      Builds project and starts cordjs server
      ###
      commands.build(options).failAloud().done (builder, buildOptions) ->
        serverOptions = normalizeServerOptions(options)
        serverProcessManager = new ServerProcessManager(_.extend(buildOptions, serverOptions))
        builder.on 'complete', ->
          console.log 'Restarting...'
          console.log '---------------------'
          serverProcessManager.restart()


    optimize: (options) ->
      handleChdir(options)
      optimizer = new Optimizer
        targetDir: "#{ process.cwd() }/#{ options.out }"
        clean: options.clean
        css: not options.disableCss
        cssMinify: not options.disableCssMinify
        js: not options.disableJs
        jsMinify: not options.disableJsMinify
      optimizer.run()


    clean: (options) ->
      console.log "Cleaning project..."
      handleChdir(options)
      rmrf(normalizeBuildOptions(options).targetDir)


  cliParser.run(commands)



handleChdir = (options) ->
  process.chdir(options.parent.chdir) if options.parent.chdir


normalizeBuildOptions = (options) ->
  curDir = process.cwd()

  baseDir: curDir
  targetDir: "#{curDir}/#{ if options.out then options.out else 'target'}"
  watch: !!options.watch
  clean: !!options.clean
  appConfigName: "#{ if options.app then options.app else 'application'}"
  indexPageWidget: options.index


normalizeServerOptions = (options) ->
  config: options.config
  port: parseInt(options.port)
