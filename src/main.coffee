_ = require 'underscore'

rmrf = require './utils/rmrf'

cliParser            = require './cli-parser'
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
      console.log "Building project with options", options
      builder  = new ProjectBuilder(normalizeBuildOptions(options))
      builder.build()


    run: (options) ->
      ###
      Builds project and starts cordjs server
      ###
      buildOptions = normalizeBuildOptions(options)
      builder = new ProjectBuilder(buildOptions)
      builder.build()
      serverOptions = normalizeServerOptions(options)
      serverProcessManager = new ServerProcessManager(_.extend(buildOptions, serverOptions))
      builder.on 'complete', ->
        console.log "build complete. restarting..."
        serverProcessManager.restart()


    clean: (options) ->
      console.log "Cleaning project..."
      rmrf(normalizeBuildOptions(options).targetDir)



normalizeBuildOptions = (options) ->
  process.chdir(options.parent.chdir) if options.parent.chdir
  curDir = process.cwd()

  baseDir: curDir
  targetDir: "#{curDir}/#{options.out}"
  watch: !!options.watch
  debug: !!options.debug


normalizeServerOptions = (options) ->
  config: options.config
  port: parseInt(options.port)
