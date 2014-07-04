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
      cleanFuture = if buildOptions.clean then commands.clean(options) else Future.resolved()
      cleanFuture.map ->
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
          console.log "build complete. restarting..."
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
  debug: !!options.debug
  clean: !!options.clean


normalizeServerOptions = (options) ->
  config: options.config
  port: parseInt(options.port)
