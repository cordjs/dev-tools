fs = require('fs')
path = require('path')
Future = require('./Future')

rmrf = (target) ->
  ###
  Recursively removes the given directory or file.
  Doesn't remove short top-level names (e.g. /usr/ or /etc/) to avoid fatal mistakes, name length must be greater than 5
  @param {String} target - absolute path to the file/directory to be removed
  @return {Future<undefined>}
  ###
  if path.resolve(target) == path.normalize(target) and target.trim().length > 5
    Future.call(fs.lstat, target).then (stat) ->
      if stat.isDirectory()
        Future.call(fs.readdir, target).then (items) ->
          futures = (rmrf(path.join(target, item)) for item in items)
          Future.all(futures)
        .then ->
          Future.call(fs.rmdir, target)
      else
        Future.call(fs.unlink, target)
    .then ->
      return
    # ignore already removed files
    .catchIf (err) ->
      err.code == 'ENOENT'
  else
    Future.rejected(new Error("Only absolute and not short top-level paths are supported, '#{target}' given!"))


module.exports = rmrf
