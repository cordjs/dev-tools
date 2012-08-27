fs              = require 'fs'
util            = require 'util'
path            = require 'path'
walk            = require 'walk'
optparse        = require './optparse'
{spawn, exec}   = require 'child_process'

publicDir   = 'public'
outputDir   = 'target'
options     = {}
sources     = []
countFiles  = null
server      = null
timerRestartServer = null
pathToNodeInit = "/bundles/cord/core/nodeInit"
baseDirFull = null

# Print if call without arguments
EmptyArguments = '''Usage: cordjs [options] path/to/project -- [args]'''

# List of options flags
OptionsList = [
  ['-a', '--autorestart',     'autorestart server']
  ['-d', '--dev',             'development mode - copy all files to the outputDir']
  ['-h', '--help',            'display this help message']
  ['-o', '--output [DIR]',    'output directory']
  ['-s', '--server',          'start server']
  ['-w', '--watch',           'watch scripts for changes and rerun commands']
]

exports.run = ->
  parseOptions()
  return usage()              if options.help
  outputDir = options.output  if options.output

  try
    baseDirFull = path.dirname( fs.realpathSync publicDir )
  catch e
    if e.code is 'ENOENT'
      timeLog "Error: no such public directory '#{publicDir}'"
      return false

  removeDirSync outputDir
  exec "mkdir -p #{ publicDir }", ->
    timeLog "Output directory created '#{outputDir}'"
    countFiles = 0
    syncFiles publicDir, path.normalize(publicDir), ->
      exec "coffee -bco #{outputDir} #{publicDir}", (e)->
        exec "sass --update #{publicDir}:#{outputDir}"
        timeLog "Synchronized #{ countFiles } files"
        if options.server
          pathToNodeInit = "#{ path.join baseDirFull, outputDir }#{ pathToNodeInit }"
          server = require pathToNodeInit

# Synchronize files
syncFiles = (source, base, callback) ->
  fs.stat source, (err, stats) ->
    return syncFile source, base if stats.isFile()

    walker = walk.walk source
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

    walker.on 'end', ->
      callback?()

# Synchronize target-file with the source
syncFile = (source, base, callback, onlyWatch = false) ->
  sources.push source     if !onlyWatch
  watchFile source, base  if !onlyWatch and options.watch
  restartServer()         if onlyWatch
  extname = path.extname source
  switch extname
    when ".coffee", ".scss", ".sass"
      if extname is ".coffee" and onlyWatch
      #        console.log 'file edit: ', "#{path.dirname outputPath(source, base)} #{source}"
        exec "coffee -bc -o #{path.dirname outputPath(source, base)} #{source}", ->
          timeLog "Update CoffeeScript '#{ source }'"
          callback?()
      else if extname is (".scss" or ".sass") and onlyWatch
        exec "sass --update #{path.dirname outputPath(source, base)}:#{source}", ->
          timeLog "Update Saas '#{ source }'"
          callback?()
      else
        callback?()
    else
      timeLog "Update file '#{ source }'" if onlyWatch
      if options.dev
        copyFile source, base, (err) -> callback?()
      else
        countFiles--
        callback?()

restartServer = ->
  return if !options.autorestart
  clearTimeout timerRestartServer
  timerRestartServer = wait 200, ->
    server.stop?()
    server = require "#{ source }/bundles/cord/core/nodeInit"


# Copy file to targetPath
copyFile = (source, base, callback) ->
  filePath = outputPath source, base
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
watchFile = (source, base) ->

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
        timeLog "Remove file '#{ source }'"
    else throw e

  sync = ->
    clearTimeout syncTimeout
    syncTimeout = wait 25, ->
      fs.stat source, (err, stats) ->
        return watchErr err if err
        return rewatch() if prevStats and stats.size is prevStats.size and
        stats.mtime.getTime() is prevStats.mtime.getTime()
        prevStats = stats
        syncFile source, base, () ->
            rewatch()
          , yes

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
            timeLog "Add file '#{ source }'"
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
          timeLog "removed #{source}"

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
  baseDir   = if base is '.' then srcDir else srcDir.substring base.length
  dir       = path.join outputDir, baseDir
  path.join dir, filename

# Use the OptionParser module to extract all options from
# `process.argv` that are specified in `SWITCHES`.
parseOptions = ->
  optionParser  = new optparse.OptionParser OptionsList, EmptyArguments
  o = options  = optionParser.parse process.argv[2..]
  if options.autorestart
    options.server = options.watch = true
  publicDir = o.arguments[0] if o.arguments.length
  return

# Print the `--help` usage message and exit
usage = ->
  printLine (new optparse.OptionParser OptionsList, EmptyArguments).help()

# Convenience for cleaner setTimeouts
wait = (milliseconds, func) -> setTimeout func, milliseconds

exists    = fs.exists or path.exists
hidden = (file) -> /\/\.|~$/.test(file) or /^\.|~$/.test file
timeLog = (message) ->
  console.log "#{(new Date).toLocaleTimeString()} - #{message}"

printLine = (line) -> process.stdout.write line + '\n'
printWarn = (line) -> process.stderr.write line + '\n'

