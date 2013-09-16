fs = require('fs')
path = require('path')
mkdirp = require('mkdirp')
BuildTask = require('./BuildTask')


class CopyFile extends BuildTask

  run: ->
    src = "#{ @params.baseDir }/#{ @params.file }"
    dst = "#{ @params.targetDir }/#{ @params.file }"

    mkdirp path.dirname(dst), (err) =>
      throw err if err
      r = fs.createReadStream(src)
      r.pipe(fs.createWriteStream(dst))
      r.on 'end', =>
        @readyPromise.resolve()



module.exports = CopyFile
