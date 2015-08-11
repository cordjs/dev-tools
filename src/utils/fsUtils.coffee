fs   = require 'fs'
path = require 'path'
_    = require 'underscore'

Future = require './Future'


exports.getDirLsStat = (dir) ->
  ###
  Retuns flat listing of the given directory with the according fs.lstat result for each item
  @param {string} dir - the ls directory
  @return {Promise.<Object.<string, StatObject>>}
  ###
  Future.call(fs.readdir, dir).then (items) ->
    promises = (Future.call(fs.lstat, path.join(dir, item)) for item in items)
    Future.all(promises).then (stats) ->
      _.object(items, stats)


exports.exists = (path) ->
  ###
  Tests if the given path exists in the file system.
  @param {string} path - file or directory path to test
  @return {Promise.<boolean>}
  ###
  Future.call(fs.stat, path).then ->
    true
  .catch (err) ->
    if err.code == 'ENOENT'
      false
    else
      throw err


exports.sourceModified = (src, dst) ->
  ###
  Detects if the source file modification time is later than the destination file's.
  @param {string} src - source file path
  @param {string} dst - destination file path
  @return {Promise.<boolean>}
  ###
  Future.all [
    Future.call(fs.stat, src)
    Future.call(fs.stat, dst)
  ]
  .spread (srcStat, dstStat) ->
    srcStat.mtime.getTime() > dstStat.mtime.getTime()
  .catch ->
    true
