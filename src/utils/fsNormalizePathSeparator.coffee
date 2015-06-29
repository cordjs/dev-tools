path = require('path')


normalizePathSeparator= (filePath) ->
  ###
  применяется для преобразования пути в юникс стайл для Windows
  ###
  if path.sep != '/'
    filePath.split(path.sep).join('/')
  else
    filePath

module.exports = normalizePathSeparator