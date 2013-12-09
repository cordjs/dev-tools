_ = require 'underscore'

rmrf = require './utils/rmrf'

cliParser            = require './cli-parser'
Optimizer            = require './optimizer/Optimizer'
ProjectBuilder       = require './build/ProjectBuilder'
ServerProcessManager = require './server/ServerProcessManager'


exports.main = ->
  ###
  Main cordjs CLI tool entry point.
  ###
  cliParser.run
    build: (options) ->
      ###
      Builds whole project.
      ###
      handleChdir(options)
      builder = new ProjectBuilder(normalizeBuildOptions(options))
      builder.build()


    run: (options) ->
      ###
      Builds project and starts cordjs server
      ###
      handleChdir(options)
      buildOptions = normalizeBuildOptions(options)
      builder = new ProjectBuilder(buildOptions)
      builder.build()
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
      optimizer.run()


    clean: (options) ->
      console.log "Cleaning project..."
      handleChdir(options)
      rmrf(normalizeBuildOptions(options).targetDir)


handleChdir = (options) ->
  process.chdir(options.parent.chdir) if options.parent.chdir


normalizeBuildOptions = (options) ->
  curDir = process.cwd()

  baseDir: curDir
  targetDir: "#{curDir}/#{ if options.out then options.out else 'target'}"
  watch: !!options.watch
  debug: !!options.debug


normalizeServerOptions = (options) ->
  config: options.config
  port: parseInt(options.port)
