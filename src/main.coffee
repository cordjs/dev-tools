exports.main = ->
  ###
  Main cordjs CLI tool entry point.
  ###
  require('./cli-parser').run
    build: (options) ->
      console.log "Building project with options", options


    run: (options) ->
      console.log "Starting cordjs server with options", options


    clean: ->
      console.log "Cleaning project..."
