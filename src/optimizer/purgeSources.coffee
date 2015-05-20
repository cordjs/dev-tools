fs = require 'fs'
path = require 'path'

Future = require '../utils/Future'
rmrf   = require '../utils/rmrf'

requirejsConfig = require './requirejsConfig'


module.exports = (targetDir) ->
  ###
  Removes source js and css files that are included into the optimized groups.
  Also removes compiled tests and empty folders.
  This procedure can be used to prepare browser-only build (e.g. phonegap).
  @param {String} targetDir - target directory of the optimized build
  @return {Future<undefined>}
  ###
  console.log "Removing source files..."
  start = process.hrtime()

  Future.require("#{targetDir}/conf/optimizer-group-cache-generated").then (groupMap) ->
    Future.all [
      purgeCssFiles(targetDir, groupMap.css)
      purgeJsFiles(targetDir, groupMap.js)
      removeTests(targetDir)
    ]
  .then ->
    console.log "Removing empty folders..."
    purgeEmptyFolders(targetDir)
  .then ->
    diff = process.hrtime(start)
    console.log "Purge sources complete in #{ (diff[0] * 1e9 + diff[1]) / 1e6 } ms"
  .failAloud('optimizer::purgeSources')



purgeCssFiles = (targetDir, groupMap) ->
  files = Object.keys(groupMap)
  removePromises =
    for relative in files
      Future.call(fs.unlink, "#{targetDir}/public#{relative}")
  Future.all(removePromises).then -> return


purgeJsFiles = (targetDir, groupMap) ->
  requirejsConfig.collect(targetDir).then (requireConfig) ->
    paths = requireConfig.paths
    files = Object.keys(groupMap)
    removePromises =
      for relative in files
        relative = paths[relative]  if paths[relative]
        Future.call(fs.unlink, "#{targetDir}/public/#{relative}.js")

    Future.all(removePromises)
  .then -> return


removeTests = (targetDir) ->
  rmrf("#{targetDir}/test")


purgeEmptyFolders = (target) ->
  ###
  Recursively deep scans the given absolute path and removes all empty directories.
  @param {String} target
  @return {Future<Boolean>} true if the path was empty directory, false otherwise
  ###
  if path.resolve(target) == path.normalize(target) and target.trim().length > 5
    Future.call(fs.lstat, target).then (stat) ->
      if stat.isDirectory()
        Future.call(fs.readdir, target).then (items) ->
          futures = (purgeEmptyFolders(path.join(target, item)) for item in items)
          Future.all(futures)
        .then (results) ->
          if results.indexOf(false) == -1
            Future.call(fs.rmdir, target).then -> true
          else
            false
      else
        false
    # ignore already removed files
    .catch (err) ->
      if err.code == 'ENOENT'
        true
      else
        throw err
  else
    Future.rejected(new Error("Only absolute and not short top-level paths are supported, '#{target}' given!"))
