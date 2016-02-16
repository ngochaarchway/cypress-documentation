@App.module "Utilities", (Utilities, App, Backbone, Marionette, $, _) ->
  msgs = {}

  addMsg = (id, event, fn) ->
    msgs[id] = {
      event: event
      fn: fn
    }

  removeMsgsByEvent = (event) ->
    msgs = _(msgs).omit (msg) ->
      msg.event is event

  removeMsgById = (id) ->
    msgs = _(msgs).omit(""+id)

  createIpc = ->
    console.warn("Missing 'ipc'. Polyfilling in development mode.")

    responses = []

    ## return a mock ipc interface useful in development + testing
    return {
      on: ->
      off: ->
      send: (resp, id, event) ->
        ## if we have a pending response then just
        ## invoke it asynchronously
        if response = _.find(responses, {event: event})
          Promise.delay(1).then =>
            @handle(event, response.err, response.data)
            response.resolve()

      handle: (event, err, data) ->
        new Promise (resolve, reject) ->
          ## create our own handle function to callback the registered events
          ##
          ## grab the first msg by its event
          msg = _.chain(msgs).where({event: event}).first().value()

          if msg
            msg.fn(err, data)
            resolve()
          else
            responses.push({
              event: event
              err: err
              data: data
              resolve: resolve
            })
    }

  ipc = window.ipc ?= createIpc()

  ipc.on "response", (event, obj = {}) ->
    {id, __error, data} = obj

    ## standard node callback implementation
    if msg = msgs[id]
      msg.fn(__error, data)

  App.ipc = (args...) ->
    return msgs if args.length is 0

    ## our ipc interface can either be a standard
    ## node callback or a promise interface
    ## we support both because oftentimes we want
    ## to our async request to be resolved with a
    ## singular value, and other times we want it
    ## to be called multiple times akin to a stream

    ## generate an id
    id = Math.random()

    ## first arg is the event
    event = args[0]

    ## get the last argument
    lastArg = args.pop()

    ## enable the last arg to be a function
    ## which changes this interface from being
    ## a promise to just calling the callback
    ## function directly
    if lastArg and _.isFunction(lastArg)
      fn = ->
        addMsg id, event, lastArg
    else
      ## push it back onto the array
      args.push(lastArg)

      fn = ->
        ## return a promise interface and at the
        ## same time store this callback function
        ## by id in msgs
        new Promise (resolve, reject) ->
          addMsg id, event, (err, data) ->
            ## cleanup messages using promise interface
            ## automatically
            removeMsgById(id)

            if err
              reject(err)
            else
              resolve(data)

    ## pass in request, id, and remaining args
    ipc.send.apply ipc, ["request", id].concat(args)

    return fn()

  App.ipc.off = (event) ->
    removeMsgsByEvent(event)