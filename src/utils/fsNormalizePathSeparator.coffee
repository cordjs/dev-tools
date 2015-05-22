path = require('path')


normalizePathSeparator= (filePath) ->
  ###
  применяется для преобразования пути в юникс стайл для Windows
  ###
  filePath.split(path.sep).join('/')


module.exports = normalizePathSeparator