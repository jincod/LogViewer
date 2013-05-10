codes = 
	37: "prev"
	39: "next"

@eventObject = {}
_.extend eventObject, Backbone.Events

$(document).keydown (e) ->
	code = codes[e.keyCode]
	if e.ctrlKey or e.metaKey and code
		eventObject.trigger code if code

do ($, window) ->
	@r = new Router()
	Backbone.history.start
    	pashState : true