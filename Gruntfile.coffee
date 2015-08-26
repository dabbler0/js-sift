path = require 'path'
fs = require 'fs'

serveNoDottedFiles = (connect, options, middlewares) ->
  # Avoid leaking .git/.svn or other dotted files from test servers.
  middlewares.unshift (req, res, next) ->
    if req.url.indexOf('/.') < 0 then return next()
    res.statusCode = 404
    res.setHeader('Content-Type', 'text/html')
    res.end "Cannot GET #{req.url}"
  return middlewares

module.exports = (grunt) ->
  # Assemble a list of files not to try to
  # do browserify on; these are the ones that contain
  # require() calls from different modules systems or
  # are already packaged.
  NO_PARSE = [
  ]

  grunt.initConfig
    pkg: grunt.file.readJSON 'package.json'

    browserify:
      build:
        files:
          'index.js': ['./index.coffee']
        options:
          transform: ['coffeeify']
          browserifyOptions:
            standalone: 'objects'
            noParse: NO_PARSE
          banner: '''
          /*
           * Date: <%=grunt.template.today('yyyy-mm-dd')%>
           */
          '''

    connect:
      testserver:
        options:
          hostname: '0.0.0.0'
          port: 8001
          middleware: serveNoDottedFiles
          keepalive: true

  grunt.loadNpmTasks 'grunt-contrib-connect'
  grunt.loadNpmTasks 'grunt-browserify'

  grunt.registerTask 'default', ['browserify']

  grunt.registerTask 'testserver', ['connect:testserver']
