fs              = require 'fs'
util            = require 'util'
path            = require 'path'
walk            = require 'walk'
optparse        = require './optparse'
{spawn, exec}   = require 'child_process'
Cordjs          = require './cordjs'
util            = require 'util'
requirejs       = require 'requirejs'

publicDir             = 'public'
outputDir             = 'target'
options               = {}
sources               = []
widgetsWaitComliler   = []
countFiles            = null
baseDirFull           = null
serverChild           = null

pathToCore      = "/bundles/cord/core/"
pathToNodeInit  = "#{ pathToCore }nodeInit"


# Print if call without arguments
EmptyArguments = " #{ 'Usage:'.bold } cordjs [options] path/to/project -- [args] ".inverse

# List of options flags
OptionsList = [
  ['-a', '--autorestart',     'autorestart server']
  ['-b', '--build',           'build project']
  ['-d', '--dev',             'development mode - copy all files to the outputDir']
  ['-h', '--help',            'display this help message']
  ['-o', '--output [DIR]',    'output directory']
  ['-s', '--server',          'start server']
  ['-v', '--version',         'display the version number']
  ['-w', '--watch',           'watch scripts for changes and rerun commands']
]

# Entry
exports.run = ->
  args = process.argv[2..]
  type = args.shift().split ':'
  command = type[1]
  if command?
    otherCommand type[0], command, args
  else
    parseOptions process.argv[2..]
    return usage()              if options.help
    return version()            if options.version
    outputDir = options.output  if options.output
    mainCommand()

# main commans - build, compile, watch, startserver, etc.
mainCommand = ->
  try
    baseDirFull = path.dirname( fs.realpathSync publicDir )
  catch e
    if e.code is 'ENOENT'
      Cordjs.utils.timeLog "Error: no such public directory '#{publicDir}'"
      return false

  removeDirSync outputDir

  Cordjs.sendCommand "mkdir -p #{ outputDir }", (error) ->
    Cordjs.utils.timeLog "Output directory created '#{outputDir}'"
    countFiles = 0
    syncFiles publicDir, path.normalize(publicDir), ->
      Cordjs.sendCommand "coffee -bco #{path.join outputDir, publicDir} #{publicDir}", (error) ->
        if error
          Cordjs.utils.timeLogError 'Coffescript compiler'
        else
          exec "sass --update #{publicDir}:#{path.join outputDir, publicDir}", (error) ->
            if error
              Cordjs.utils.timeLogError 'Sass compiler'

          return syncFiles 'node_modules', path.normalize('node_modules'), completeSync if options.build
          completeSync()

  completeSync = ->
    Cordjs.sendCommand "coffee -bc -o #{ outputDir } server.coffee", (error) ->
      if error
        Cordjs.utils.timeLogError 'Coffescript compiler'
      else
        initCompileWidgets ->
          countFiles++
          Cordjs.utils.timeLog "Synchronized #{ countFiles } files"
          if options.server
            pathToNodeInit = "#{ path.join baseDirFull, outputDir, publicDir, pathToNodeInit }"

            startServer()

  initCompileWidgets = (callback) ->
    configPaths = require "#{ path.join baseDirFull, outputDir, publicDir, pathToCore }configPaths"

    baseUrl = path.join outputDir, publicDir
    requirejs.config
      baseUrl: baseUrl
      nodeRequire: require

    requirejs.config configPaths

    requirejs [
      "cord!config"
    ], (config) ->
      config.PUBLIC_PREFIX = baseUrl

      widgetsWaitComliler = []
      widgetsPaths = {}

      for source in sources
        extname = path.extname source
        if extname is '.coffee' and parseInt(source.indexOf '/widgets/') > 0
          dirname = getWidgetPath source

          if !widgetsPaths[dirname]
            widgetsPaths[dirname] = dirname
            widgetsWaitComliler.push dirname

      compileWidget callback


getWidgetPath = (source) ->
  source = path.dirname source
  source = source.replace 'public/bundles', ''
  source = source.replace '/widgets/', '//'

  widgetClassName = path.basename source
  widgetClassName = widgetClassName.charAt(0).toUpperCase() + widgetClassName.slice(1)

  pathToWidget = source.split '/'
  pathToWidget.pop()

  "#{ pathToWidget.join '/' }/#{ widgetClassName }"


compileWidget = (callback) ->
  widgetName = widgetsWaitComliler.pop()
  if !widgetName?
    return callback?()

  requirejs [
    "cord-w!#{ widgetName }"
    "cord!widgetCompiler"
    "cord!config"
  ], (WidgetClass, widgetCompiler, config) =>

    widget = new WidgetClass true
    widgetCompiler.reset widget

    widget.compileTemplate (err, output) =>
      if err then throw err
      tmplFullPath = "./#{ config.PUBLIC_PREFIX }/bundles/#{ widget.getTemplatePath() }.structure.json"

      fs.writeFile tmplFullPath, widgetCompiler.getStructureCode(false), (err)->
        compileWidget callback

# other commands - create project, bundle, etc
otherCommand = (type, command, args) ->
  if Cordjs.Generator.exists type
    Cordjs.Generator.do type, command, args
  else
    console.log "Generator #{ type } not found. Available generators: #{ Cordjs.Generator.list() }"


create = (type) ->
  type = type.shift()

  if !type?
    console.log 'What create: app or bundle?'

  else if !Cordjs.creator.exist type
    console.log "Generator #{ type } not found"

  console.log 'type: ', type

# start server
startServer = ->
  serverChild = spawn "node", [path.join(outputDir, 'server.js'), path.join(outputDir, publicDir)]

  serverChild.stdout.on 'data', (data) ->
    util.print data

  serverChild.stderr.on 'data', (error) ->
    util.print error

# stop server
stopServer = ->
  serverChild?.kill()

# restart server
restartServer = ->
  stopServer()
  startServer()
  Cordjs.utils.timeLog 'Server restarted'

# Synchronize files
syncFiles = (source, base, callback) ->
  fs.stat source, (err, stats) ->
    return syncFile source, base if stats.isFile()

    walker = walk.walk source, { followLinks: false }
    walker.on 'directory', (root, stat, next) ->
      source = path.join root, stat.name
      return next()           if hidden source
      watchDir source, base   if options.watch
      next()

    walker.on 'file', (root, stat, next) ->
      source = path.join root, stat.name
      return next() if hidden source
      syncFile source, base, ->
        countFiles++
        next()
      next()

    walker.on 'symbolicLink', (root, stat, next) ->
      symbolicLink = path.join root, stat.name
      dirname = path.dirname symbolicLink
      source = path.join dirname, fs.readlinkSync(symbolicLink)
      return next() if hidden symbolicLink
      syncFile source, base, ->
        countFiles++
        next()
      , false, symbolicLink
      next()

    walker.on 'end', ->
      callback?()

# Synchronize target-file with the source
syncFile = (source, base, callback, onlyWatch = false, symbolicLink) ->
  baseSource = (if symbolicLink then symbolicLink else source)
  sources.push baseSource                   if !onlyWatch
  watchFile baseSource, base, symbolicLink  if !onlyWatch and options.watch
  extname = path.extname baseSource

  if onlyWatch
    widgetsWaitComliler.push getWidgetPath(source)

  completeSync = ->
    compileWidget callback

  switch extname
    when ".coffee", ".scss", ".sass"

      if extname is ".coffee" and onlyWatch
        Cordjs.sendCommand "coffee -bco #{path.dirname outputPath(baseSource, base)} #{source}", (error) ->
          if error
            Cordjs.utils.timeLogError "Coffescript compiler '#{ baseSource }'"
          else
            Cordjs.utils.timeLog "Update CoffeeScript '#{ baseSource }'"
          completeSync()

      else if extname is (".scss" or ".sass") and onlyWatch
        exec "sass --update #{path.dirname outputPath(baseSource, base)}:#{source}", (error) ->
          if error
            Cordjs.utils.timeLogError 'Sass compiler'
          else
            Cordjs.utils.timeLog "Update Saas '#{ baseSource }'"
          completeSync()

      else
        completeSync()

    else
      Cordjs.utils.timeLog "Update file '#{ baseSource }'" if onlyWatch
      if options.dev or options.build
        copyFile source, base, (err) ->
          completeSync()
        , symbolicLink

      else
        countFiles--
        completeSync()

# Copy file to targetPath
copyFile = (source, base, callback, symbolicLink) ->
  filePath = outputPath (if symbolicLink then symbolicLink else source), base
  fileDir  = path.dirname filePath

  copyHelper = () ->
    fs.stat source, (err, stat) ->
      callback? err if err
      util.pump fs.createReadStream(source), fs.createWriteStream(filePath), (err) ->
        callback? err if err
        fs.utimes filePath, stat.atime, stat.mtime, callback

  exists fileDir, (itExists) ->
    if itExists then copyHelper() else exec "mkdir -p #{fileDir}", copyHelper

# Watch a source file using `fs.watch`, recompiling it every
# time the file is updated.
watchFile = (source, base, symbolicLink) ->

  prevStats = null
  syncTimeout = null

  watchErr = (e) ->
    if e.code is 'ENOENT'
      return if sources.indexOf(source) is -1
      try
        rewatch()
        sync()
      catch e
        removeSource source, base, yes
        Cordjs.utils.timeLog "Remove file '#{ source }'"
    else
      if e.code is 'EMFILE'
        Cordjs.utils.timeLogError "Max limit opened files. Try change limit. #{ 'For mac use: ulimit -n 65536'.yellow }"
      throw e

  sync = ->
    clearTimeout syncTimeout
    syncTimeout = wait 25, ->
      fs.stat source, (err, stats) ->
        return watchErr err if err
        return rewatch() if prevStats and stats.size is prevStats.size and
        stats.mtime.getTime() is prevStats.mtime.getTime()
        prevStats = stats
        syncFile source, base, () ->
            restartServer() if options.server
            rewatch()
        , yes, symbolicLink

  try
    watcher = fs.watch source, sync
  catch e
    watchErr e

  rewatch = ->
    watcher?.close()
    watcher = fs.watch source, sync

# Watch a directory of files for new adds
watchDir = (source, base) ->
  readdirTimeout = null
  try
    watcher = fs.watch source, ->
      clearTimeout readdirTimeout
      readdirTimeout = wait 25, ->
        fs.readdir source, (err, files) ->
          if err
            throw err unless err.code is 'ENOENT'
            watcher.close()
            return unwatchDir source, base
          for file in files
            file = path.join source, file
            continue if sources.some (s) -> s.indexOf(file) >= 0
            Cordjs.utils.timeLog "Add file '#{ source }'"
            sources.push file
            syncFiles file, base
  catch e
    throw e unless e.code is 'ENOENT'

# Unwatch and remove directory
unwatchDir = (source, base) ->
  prevSources = sources[..]
  toRemove = (file for file in sources when file.indexOf(source) >= 0)
  removeSource file, base, yes for file in toRemove
  return unless sources.some (s, i) -> prevSources[i] isnt s

# Remove source from targetPath
removeSource = (source, base, remove) ->
  index = sources.indexOf source
  sources.splice index, 1
  if remove
    outPath = outputPath source, base
    exists outPath, (itExists) ->
      if itExists
        fs.unlink outPath, (err) ->
          throw err if err and err.code isnt 'ENOENT'
          Cordjs.utils.timeLog "removed #{source}"

#Remove dir
removeDirSync = (source) ->
  try
    for file in fs.readdirSync source
      filename = path.join source, file
      stat = fs.statSync filename
      continue if filename is "." or filename == ".."
      if stat.isDirectory()
        removeDirSync filename
      else
        fs.unlinkSync filename
    fs.rmdirSync source
  catch e
    throw e unless e.code is 'ENOENT'

# Get output path
outputPath = (source, base) ->
  filename  = path.basename source
  srcDir    = path.dirname source
#  baseDir   = if base is '.' then srcDir else srcDir.substring base.length
  baseDir   = srcDir
  dir       = path.join outputDir, baseDir
  path.join dir, filename

# Use the OptionParser module to extract all options from
# `process.argv` that are specified in `SWITCHES`.
parseOptions = (args) ->
  optionParser  = new optparse.OptionParser OptionsList, EmptyArguments
  o = options  = optionParser.parse args
  if options.autorestart
    options.server = options.watch = true
  publicDir = o.arguments[0] if o.arguments.length

# Print the `--help` usage message and exit
usage = ->
  printLine (new optparse.OptionParser OptionsList, EmptyArguments).help()

# Print the `--version` message and exit
version = ->
  printLine "Cordjs current version: #{Cordjs.VERSION.green}"

# Convenience for cleaner setTimeouts
wait = (milliseconds, func) -> setTimeout func, milliseconds

exists    = fs.exists or path.exists
hidden = (file) -> /\/\.|~$/.test(file) or /^\.|~$/.test file

printLine = (line) -> process.stdout.write line + '\n'
printWarn = (line) -> process.stderr.write line + '\n'

