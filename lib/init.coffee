path    = require 'path'
open    = require 'open'
request = require 'request'
urljoin = require 'url-join'
fs      = require 'fs'

{CompositeDisposable} = require 'atom'

suggestions = (a, pos) ->
  fixes = []

  request.post
    url: 'http://localhost:7777/suggest',
    form:
      alert: JSON.stringify(a)
  , (err, res, ret) ->
    if not err and res.statusCode is 200
      if ret
        for suggestion in JSON.parse(ret)['suggestions']
          fixes.push
            position: pos
            currentText: a.Match
            replaceWith: suggestion

  fixes


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

    @subscriptions.add atom.commands.add 'atom-workspace', 'vale-server:open-dashboard', ->
      open('http://localhost:7777/')

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
            url: urljoin(@valePath, 'file'),
            form:
              file: loc,
              path: path.dirname(loc)
          , (err, res, output) ->
            if not err and res.statusCode is 200
              results = JSON.parse(output)
              content = fs.readFileSync(results.path, 'utf8')

              feedback = JSON.parse(content.toString())
              messages = []

              for f, alerts of feedback
                for alert in alerts
                  rule = alert.Check.split '.'
                  floc = [
                    [alert.Line - 1, alert.Span[0] - 1]
                    [alert.Line - 1, alert.Span[1]]
                  ]

                  messages.push
                    severity: if alert.Severity == 'suggestion' then 'info' else alert.Severity
                    solutions: suggestions(alert, floc)
                    location:
                      file: loc
                      position: floc
                    excerpt: alert.Message
                    linterName: "[Vale Server] #{alert.Check}"
                    url: alert.Link
                    description: alert.Description
                    reference:
                      file: path.join styles, rule[0], rule[1] + '.yml'

              resolve messages
            else
              atom.notifications.addError '[Vale Server] could not connect.',
                detail: err
                dismissable: true

        return new Promise (resolve, reject) =>
          runLinter(resolve)
