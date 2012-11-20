###
	module package to help accessing basecamp-2 api
     
    todo:
    	check for expired accesses
###

url		= require 'url'
_		= require 'underscore'
request = require 'request'

opPaths = null

exports.Client = class Client
 
	constructor: (@client_id, @client_secret, @redirect_uri, @userAgent) -> 

	getAuthNewUrl: (state) ->
		"https://launchpad.37signals.com/authorization/new" +
		"?type=" 				 + 'web_server' +
		"&client_id=" 			 + @client_id +
		"&redirect_uri=" 		 + encodeURIComponent(@redirect_uri) +
		(if state then "&state=" + encodeURIComponent(JSON.stringify state) else '')
		
	authNewCallback: (req, res, cb) ->
		query = url.parse(req.url, true).query
		
		if not query.code or query.error
			console.log 'basecamp: err in authorization/new callback: ' + req.url
			res.end()
			cb?()
			return
			
		@_getToken query, null, (err, userInfo, html) ->
			res.end html
			cb? err, userInfo
 
	_getToken: (cbQuery, refresh_token, cb) ->
			
		tokenUrl = "https://launchpad.37signals.com/authorization/token" +
					"?client_id=" 		+ @client_id +
					"&redirect_uri=" 	+ encodeURIComponent(@redirect_uri) +
					"&client_secret=" 	+ @client_secret
					
		form = {@client_id, @redirect_uri, @client_secret}
			
		if cbQuery
			tokenUrl += '&type=web_server&code=' + cbQuery.code
			_.extend form, code: cbQuery.code
			state = JSON.parse cbQuery.state ? '{}'
			href = state.href ? '/'
			html = """
				<html><head>
					<meta http-equiv="REFRESH" content="0;url=#{href}">
				</head><body></body></html> """
		else
			tokenUrl += '&type=refresh&refresh_token=' + refresh_token
			_.extend form, {refresh_token}
			
		request 
			method: 'POST'
			uri:    tokenUrl
			form:   form
		
		, (error, response, bodyJSON) ->   # error authorization_expired

			if error or bodyJSON.indexOf('"error":') isnt -1
			
				console.log '\nbasecamp: token request error\n', {error, bodyJSON, cbQuery, refresh_token}
				
				cb? 'token request error'
				return
				
			tokenResp = JSON.parse bodyJSON
			
			request
				url: 'https://launchpad.37signals.com/authorization.json'
				headers: Authorization: 'Bearer ' + tokenResp.access_token
				
			, (error, response, bodyJSON) ->
				if error or bodyJSON.indexOf('error:') isnt -1
				
					msg =  '\nbasecamp: error from authorization request\n'
					console.log msg, {cbQuery, refresh_token, error, bodyJSON}
					
					cb? msg
					return
				
				userInfo = _.extend tokenResp, JSON.parse(bodyJSON), (if state then {state})
				cb? null, userInfo, html
				
exports.Account = class Account

	constructor: (@client, @accountId, refresh_token, cb) ->
	
		@account = null
		
		client._getToken null, refresh_token, (@err, @userInfo) =>
			
			if @err or not @userInfo.accounts
				console.log '\nbasecamp: _getToken error', 
							@accountId, refresh_token, @err, @userInfo
				cb? '_getToken error'
				return
			
			for account in @userInfo.accounts
				if account.id is @accountId
					@account = account
					break
					
			if not @account
				@err = 'basecamp: account not found, ' + 
						@userInfo.identity.email_address + ', ' + @accountId
				console.log '\nbasecamp ' + @err
				cb @err
				return 
			
			if @account?.product isnt 'bcx'
				@err = 'basecamp: error, product ' + account?.product + ' not supported, ' + 
							@userInfo.identity.email_address + ', ' + @accountId
				console.log '\nbasecamp ' + @err
				cb @err
				return
			
			cb null, @
			
	req: (opts, cb) ->
	
		if not @account then cb 'basecamp: req error, no account'; return
		
		if typeof opts is 'string'
			opts = op: opts
		op = opts.op
	
		if not (path = opPaths[op]) 
			cb 'basecamp: req error, invalid opcode ' + op
			return
			
		requestOpts = 
			headers: 
				'User-Agent':  @client.userAgent
				Authorization: 'Bearer ' + @userInfo.access_token
				
		if path[0] is 'P'
			if not opts.body then cb 'basecamp: post/put req body missing ' + op, opts; return
			
			requestOpts.method = path.split('/')[0]
			path = path[requestOpts.method.length ..]
			requestOpts.body = JSON.stringify opts.body  # encodeURIComponent ?
			
		if path.indexOf('~projectId~') isnt -1
			if not opts.projectId then cb 'req error'; return
			path = path.replace '~projectId~', opts.projectId
 				
		requestOpts.url = @account.href + path
				
		request requestOpts, (error, response, bodyTxt) =>
		
			if error
				console.log '\nbasecamp: req error, bad response ' + op + 
							' ' + @account.name, error
				cb error
				return
			
			body = JSON.parse bodyTxt
			
#			console.log '\nbasecamp: req response ' + op + ' ' +
#						@userInfo.identity.email_address + ' ' + @account.name, body
			
			cb null, body


exports.Project = class Project

	constructor: (@account, @projectId) ->
 	
	req: (opts, cb) ->
		if typeof opts is 'string'
			opts = {op: opts, @projectId}
		else
			opts = _.extend {}, opts, {@projectId}
			
		@account.req opts, cb


opPaths =
	get_projects: 			'/projects.json'
	get_projects_archived: 	'/projects/archived.json'
	create_project: 		'POST/projects.json'
	
	get_project:			'/projects/~projectId~.json'
	get_topics:				'/projects/~projectId~/topics.json'