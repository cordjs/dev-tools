cliParser = require('./cli-parser')
ProjectBuilder = require('./build/ProjectBuilder')

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
      console.log "Starting cordjs server with options", options
      builder = new ProjectBuilder(normalizeBuildOptions(options))
      builder.build()
      builder.on 'complete', ->
        # restart server


    clean: ->
      console.log "Cleaning project..."


normalizeBuildOptions = (options) ->
  process.chdir(options.parent.chdir) if options.parent.chdir
  curDir = process.cwd()

  baseDir: curDir
  targetDir: "#{curDir}/#{options.out}"
  watch: !!options.watch
  debug: !!options.debug
