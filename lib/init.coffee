path    = require 'path'
request = require 'request'
urljoin = require 'url-join'

{CompositeDisposable} = require 'atom'

module.exports =
  config:
    valePath:
      type: 'string'
      title: 'URL of your Vale Server instance.'
      default: 'http://127.0.0.1:7777'

    lintOnFly:
      type: 'boolean'
      title: 'Run Vale Server on file changes (not only after saving).'
      default: true

    grammarScopes:
      type: 'array'
      title: 'List of scopes that Vale Server will lint.'
      default: [
        # Markdown
        'text.md'
        'source.gfm'
        # reStructuredText
        'text.restructuredtext'
        # AsciiDoc
        'source.asciidoc'
        # Plain text
        'text.git-commit'
        'text.plain'
        'text.plain.null-grammar'
      ]

  activate: =>
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.observe 'vale-server.valePath',
        (valePath) =>
          @valePath = valePath

    @subscriptions.add atom.config.observe 'vale-server.lintOnFly',
      (lintOnFly) =>
        @lintOnFly = lintOnFly

    @subscriptions.add atom.config.observe 'vale-server.grammarScopes',
      (grammarScopes) =>
        @grammarScopes = grammarScopes

  deactivate: =>
      @subscriptions.dispose()

  provideLinter: =>
    provider =
      name: 'Vale Server'
      grammarScopes: @grammarScopes
      scope: 'file'
      lintsOnChange: @lintOnFly

      lint: (textEditor) =>
        loc = textEditor.getPath()
        ext = path.extname(loc)

        output = ''
        styles = ''

        request.get
          url: urljoin(@valePath, 'path')
          json: true
        , (err, res, body) ->
          if not err and res.statusCode is 200
            styles = body.path

        runLinter = (resolve) =>
          request.post
            url: urljoin(@valePath, 'vale'),
            form:
              format: ext
              text: textEditor.getText()
          , (err, res, output) ->

            if output.length <= 3 # if empty object
              output = "{\"stdin#{ext}\": []}"

            feedback = JSON.parse(output)["stdin#{ext}"]
            messages = []

            for alert in feedback
              atomMessageLine = alert.Line - 1
              atomMessageRow  = alert.Span[0] - 1

              rule = alert.Check.split '.'
              messages.push
                severity: if alert.Severity == 'suggestion' then 'info' else alert.Severity
                location:
                  file: loc
                  position: [
                    [atomMessageLine, atomMessageRow]
                    [atomMessageLine, alert.Span[1]]
                  ]
                excerpt: alert.Message
                linterName: "[Vale Server] #{alert.Check}"
                url: alert.Link
                description: alert.Description
                reference:
                  file: path.join styles, rule[0], rule[1] + '.yml'

            resolve messages

        return new Promise (resolve, reject) =>
          runLinter(resolve)
