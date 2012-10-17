fs              = require 'fs'
util            = require 'util'
path            = require 'path'
walk            = require 'walk'
commander       = require 'commander'
{spawn, exec}   = require 'child_process'
Cordjs          = require './cordjs'
CoffeeScript    = require './coffee-script'
util            = require 'util'
requirejs       = require 'requirejs'
Stylus          = require 'stylus'
nib             = require 'nib'

publicDir = basePath  = 'public'
outputDir             = 'target'
watchModeEnable       = false
sources               = []
widgetsWaitComliler   = []
aFiles =
  sync: []
  copy: []

baseDirFull     = null
serverChild     = null
timeStart       =
timeEnd         = null
isServerRestart = false

pathToCore      = "/bundles/cord/core/"
pathToNodeInit  = "#{ pathToCore }nodeInit"


# Print if call without arguments
EmptyArguments = " #{ 'Usage:'.bold } cordjs [options] path/to/project -- [args] ".inverse


# List of options flags
commander
  .option('-a, --autorestart',  'autorestart server')
  .option('-b, --build',        'build project')
  .option('-c, --clean',        'clean target')
  .option('-d, --dev',          'development mode - copy all files to the outputDir')
  .option('-o, --output [dir]', 'output directory [' + outputDir + ']', outputDir)
  .option('-s, --server',       'start server')
  .option('-w, --watch',        'watch scripts for changes and rerun commands')
  .version(Cordjs.VERSION, '-v, --version')

commander
  .on '--help', ->
    printLine "Cordjs current version: #{Cordjs.VERSION.green}"
    printLine ""

commander
  .command('core [env]')
  .description('     update'.grey + ' - pulling from github')
  .action (env) ->
    switch env
      when 'update'
        return Cordjs.utils.timeLogError 'Can\'t find cord/core!' if !fs.existsSync 'public/bundles/cord/core'
        Cordjs.utils.timeLog 'Update core...'
        Cordjs.sendCommand "cd public/bundles/cord; git pull; cd -", ->
          Cordjs.utils.timeLog 'Update core complete!'
      else
        Cordjs.utils.timeLog 'Nothing todo'


# Entry
exports.run = ->
  commander
    .parse(process.argv)

  outputDir = commander.output                if commander.output
  commander.server = commander.watch = true   if commander.autorestart

  if !commander.args.length
    mainCommand()

#  args = process.argv[2..]
#  type = args.shift().split ':'
#  command = type[1]
#  if command?
#    otherCommand type[0], command, args
#  else
#    parseOptions process.argv[2..]
#    return usage()              if options.help
#    return version()            if options.version
#    outputDir = options.output  if options.output


# main commands - build, clean, compile, watch, startserver, etc.
mainCommand = ->
  return false if !testCommandDir()
  removeDirSync outputDir if commander.clean

  _startTimer()

  console.log " "
  console.log " "
  console.log "           Cordjs tools version:  #{Cordjs.VERSION.green}"
  console.log " "
  console.log " "

  createDir (outputDir), (existDir) ->
    Cordjs.utils.timeLog "Output directory created '#{outputDir}'" if !existDir

    aFiles.sync = []
    aFiles.compile = []

    basePath = path.normalize publicDir

    syncFiles publicDir, basePath, ->
      exec "sass --update #{publicDir}:#{path.join outputDir, publicDir}", (error) ->
        Cordjs.utils.timeLogError 'Sass compiler' if error?

        return syncFiles 'node_modules', path.normalize('node_modules'), completeSync if commander.build
        completeSync()


  completeSync = ->
    syncFiles 'server.coffee', '.', ->
      initCompileWidgets ->
        countCompiled = (if aFiles.compile.length then "#{ aFiles.compile.length  }".green else "#{ aFiles.compile.length  }".grey)
        Cordjs.utils.timeLog "Sync files is complete! Total " + "#{ aFiles.sync.length }".yellow + " files, #{ countCompiled } files compiled"
        Cordjs.utils.timeLog "Compiled files: " + "#{ aFiles.compile.join ', ' }".yellow  if !commander.clean and aFiles.compile.length
        watchModeEnable = true if commander.watch
        _endTimer()

        if commander.server
          pathToNodeInit = "#{ path.join baseDirFull, outputDir, publicDir, pathToNodeInit }"
          startServer()


  initCompileWidgets = (callback) ->
    return callback?() if !commander.build && !commander.dev
    configPaths = require "#{ path.join baseDirFull, outputDir, publicDir, pathToCore }configPaths"

    baseUrl = path.join outputDir, publicDir
    requirejs.config
      baseUrl: baseUrl
      nodeRequire: require

    requirejs.config configPaths

    requirejs [
      "cord!configPaths"
    ], (configPaths) ->
      configPaths.PUBLIC_PREFIX = baseUrl
      compileWidget callback


testCommandDir = ->
  try
    baseDirFull = path.dirname( fs.realpathSync publicDir )
    true
  catch e
    if e.code is 'ENOENT'
      Cordjs.utils.timeLog "Error: no such public directory '#{publicDir}'"
    false


createDir = (dir, callback) ->
  try
    dirFull = path.dirname( fs.realpathSync dir )
    callback?(dirFull)
  catch e
    if e.code is 'ENOENT'
      Cordjs.sendCommand "mkdir -p #{ dir }", (error) ->
        if error
          util.print error
        callback?()


getWidgetPath = (source) ->
  source = path.dirname source
  source = source.replace 'public/bundles', ''
  source = source.replace '/widgets/', '//'

  widgetClassName = path.basename source
  widgetClassName = widgetClassName.charAt(0).toUpperCase() + widgetClassName.slice(1)

  pathToWidget = source.split '/'
  pathToWidget.pop()

  "#{ pathToWidget.join '/' }/#{ widgetClassName }"


addWidgetWaitCompiler = (source) ->
  return if parseInt( source.indexOf '/widgets/' ) < 0 or parseInt( source.indexOf '.html' ) < 0

  return if path.basename(path.dirname(source)) != path.basename(source, path.extname(source))

  dirname = getWidgetPath source
  return if widgetsWaitComliler.some (s) -> s.indexOf(dirname) >= 0
  if isDiffSource path.dirname(source), outputPath(path.dirname(source), basePath)
    widgetsWaitComliler.push dirname


compileWidget = (callback) ->
  widgetName = widgetsWaitComliler.pop()
  if !widgetName?
    return callback?()

  requirejs [
    "cord-w!#{ widgetName }"
    "cord!widgetCompiler"
  ], (WidgetClass, widgetCompiler) =>

    widget = new WidgetClass
      compileMode: true

    widgetCompiler.reset widget

    widget.compileTemplate (err, output) =>
      if err then throw err
      source = "#{ publicDir }/bundles/#{ widget.getTemplatePath() }.structure.json"
      outputSource = outputPath source, path.normalize( publicDir )

      fs.writeFile outputSource, widgetCompiler.getStructureCode(false), (err)->
        fs.stat path.dirname( source ), (err, stat) =>
          fs.utimes path.dirname( outputSource ), stat.atime, stat.mtime
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


# start server
iErrServerStart = 0
timerErrServer = null

startServer = ->
  serverChild = spawn "node", [path.join(outputDir, 'server.js'), path.join(outputDir, publicDir)]

  serverChild.stdout.on 'data', (data) ->
#    iErrServerStart = 0
    util.print data

  serverChild.stderr.on 'data', (error) ->
    util.print error

  serverChild.on 'exit', (code) ->
    return if isServerRestart or !commander.autorestart
    if iErrServerStart > 1
      Cordjs.utils.timeLogError "Can't restart server. Code error '#{ code }'"
      return process.exit 1
    iErrServerStart++
    restartServer()


# stop server
stopServer = ->
  serverChild?.kill()


# restart server
restartServer = ->
  isServerRestart = true
  stopServer()
  startServer()
  wait 10, =>
    isServerRestart = false

  clearTimeout timerErrServer
  timerErrServer = setTimeout =>
      iErrServerStart = 0
    , 1000
  Cordjs.utils.timeLog 'Server restarted'


# Synchronize files
syncFiles = (source, base, callback) ->
  fs.stat source, (err, stats) ->
    if stats.isFile()
      return syncFile source, base, ->
        aFiles.sync.push source
        callback?()

    walker = walk.walk source, { followLinks: false }
    walker.on 'directory', (root, stat, next) ->
      source = path.join root, stat.name
      return next()           if hidden source
      watchDir source, base   if commander.watch
      next()

    walker.on 'file', (root, stat, next) ->
      source = path.join root, stat.name
      return next() if hidden source
      syncFile source, base, ->
        aFiles.sync.push source
        next()
      next()

    walker.on 'symbolicLink', (root, stat, next) ->
      symbolicLink = path.join root, stat.name
      dirname = path.dirname symbolicLink
      source = path.join dirname, fs.readlinkSync(symbolicLink)
      return next() if hidden symbolicLink
      syncFile source, base, ->
        aFiles.sync.push source
        next()
      , false, symbolicLink
      next()

    walker.on 'end', ->
      callback?()


# Synchronize target-file with the source
syncFile = (source, base, callback, onlyWatch = false, symbolicLink) ->
  baseSource = (if symbolicLink then symbolicLink else source)
  sources.push baseSource                   if !onlyWatch
  watchFile baseSource, base, symbolicLink  if !onlyWatch and commander.watch
  extname = path.extname baseSource

  addWidgetWaitCompiler source
#  if onlyWatch and parseInt(source.indexOf '/widgets/') > 0
#    widgetsWaitComliler.push getWidgetPath(source)

  completeSync = ->
    return callback?() if !watchModeEnable
    compileWidget callback

  if extname is ".scss" or extname is ".sass"
    if !watchModeEnable
      aFiles.compile.push source
      return completeSync()

    exec "sass --update #{path.dirname outputPath(baseSource, base)}:#{source}", (error) ->
      if error?
        Cordjs.utils.timeLogError "Sass: #{ source }"
      else
        Cordjs.utils.timeLog "Update Saas '#{ source }'"

      completeSync()

  else if commander.dev or commander.build
    copyFile source, base, (err) ->
      addWidgetWaitCompiler baseSource
      completeSync()
    , symbolicLink

  else
    completeSync()


# Copy file to targetPath
copyFile = (source, base, callback, symbolicLink) ->
  filePath = outputPath (if symbolicLink then symbolicLink else source), base
  fileDir  = path.dirname filePath

  sourceStat = null

  copyCallback = ->
    aFiles.compile.push source
    fs.utimes filePath, sourceStat.atime, sourceStat.mtime, callback
    fs.stat path.dirname( source ), (err, stat) =>
      fs.utimes fileDir, stat.atime, stat.mtime

    Cordjs.utils.timeLog "Update file '#{ source }'" if watchModeEnable

  copyHelper = () ->
    fs.stat source, (err, stat) =>
      sourceStat = stat
      callback? err if err

      return callback?() if !isDiffSource source, filePath

      extname = path.extname source

      # render coffee-script
      if extname is '.coffee'
        CoffeeScript.compile source, base, commander, (jsCode) ->
          fs.writeFile filePath, jsCode, (err) ->
            if err
              printLine err.message
            copyCallback()

      # render stylus
      else if extname is '.styl'
        str = fs.readFileSync source, 'utf8'

        regexCord = /(["'])cord-s!([\w/]+)/gi
        search = str.search regexCord
        str = str.replace regexCord, (text, p1, p2) ->
          return p1 + "."

        if ~search
          console.log source
          throw "Waiting to Davojan's convert-method..."
          process.exit 1

        Stylus("@import 'nib' \n\n" + str)
        .set('filename', source)
        .define('url', Stylus.url())
        .use(nib())
#        .include('public')
#        .include(source.slice( 0, source.indexOf( '/widgets/' ) + '/widgets/'.length ))
        .render (err, css) ->
          if err
            Cordjs.utils.timeLogError "Stylus: #{ source }"
            printWarn err
#            process.exit 1

          fs.writeFile filePath, css, (err) ->
            if err
              printLine err.message
            copyCallback()

      # simple copy
      else
        util.pump fs.createReadStream(source), fs.createWriteStream(filePath), (err) ->
          return callback? err if err?
          copyCallback()

  exists fileDir, (itExists) ->
    if itExists then copyHelper() else exec "mkdir -p #{fileDir}", copyHelper


# Check diffents source
isDiffSource = ( baseSource, outputSource, baseStat, outputStat ) ->
  baseStat = fs.statSync baseSource if !baseStat?
  try
    outputStat = fs.statSync outputSource if !outputStat?
    if outputStat.isDirectory() or path.extname(baseSource) is '.coffee'
      return false if baseStat.mtime.getTime() is outputStat.mtime.getTime()
    else
      return false if outputStat.size is baseStat.size and baseStat.mtime.getTime() is outputStat.mtime.getTime()
  return true


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
            restartServer() if commander.server
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
            continue if hidden file
            Cordjs.utils.timeLog "Add file '#{ file }'"
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
  filename = path.basename(source, path.extname(source)) + '.js'  if path.extname(source) is '.coffee'
  filename = path.basename(source, path.extname(source)) + '.css' if path.extname(source) is '.styl'
  srcDir    = path.dirname source
  baseDir   = srcDir
  dir       = path.join outputDir, baseDir
  path.join dir, filename


_startTimer = ->
  timeStart = new Date()


_endTimer = ->
  timeEnd = new Date()
  Cordjs.utils.timeLog "Timer: " + ( timeEnd - timeStart ) + " milliseconds"


# Convenience for cleaner setTimeouts
wait = (milliseconds, func) -> setTimeout func, milliseconds

exists      = fs.exists
existsSync  = fs.existsSync
hidden = (file) -> /\/\.|~$/.test(file) or /^\.|~$/.test file

printLine = (line) -> process.stdout.write line + '\n'
printWarn = (line) -> process.stderr.write line + '\n'
