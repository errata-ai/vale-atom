path    = require 'path'
open    = require 'open'
request = require 'request'
urljoin = require 'url-join'
fs      = require 'fs'

{CompositeDisposable} = require 'atom'

suggestions = (a, pos, path) ->
  fixes = []
  request.post
    url: urljoin(path, 'suggest'),
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

    offerSuggestions:
      type: 'boolean'
      title: 'Offer potential solutions to alerts using the \'Fix\' button.'
      default: true

  activate: =>
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.observe 'vale-server.valePath',
        (valePath) =>
          @valePath = valePath

    @subscriptions.add atom.config.observe 'vale-server.lintOnFly',
      (lintOnFly) =>
        @lintOnFly = lintOnFly

    @subscriptions.add atom.config.observe 'vale-server.offerSuggestions',
      (offerSuggestions) =>
        @offerSuggestions = offerSuggestions

    @subscriptions.add atom.config.observe 'vale-server.grammarScopes',
      (grammarScopes) =>
        @grammarScopes = grammarScopes

  deactivate: =>
      @subscriptions.dispose()

  provideLinter: =>
    provider =
      name: 'Vale Server'
      grammarScopes: '*'
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
          instance = @valePath
          fixes = @offerSuggestions

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
                    solutions: if fixes then suggestions(alert, floc, instance) else []
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
