# Credentials for a remote system
#
# Copyright 2012 E14N https://e14n.com/
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
Step = require("step")
databank = require("databank")
_ = require("underscore")
wf = require("webfinger")
querystring = require("querystring")
urlparse = require("url").parse
Stamper = require("../stamper").Stamper
ActivityObject = require("./activityobject").ActivityObject
DatabankObject = databank.DatabankObject
NoSuchThingError = databank.NoSuchThingError
Credentials = DatabankObject.subClass("credentials")
Credentials.schema =
  pkey: "host_and_id"
  fields: [
    "host"
    "id"
    "client_id"
    "client_secret"
    "expires_at"
    "created"
    "updated"
  ]
  indices: [
    "host"
    "id"
    "client_id"
  ]

Credentials.makeKey = (host, id) ->
  unless id
    host
  else
    host + "/" + id

Credentials.beforeCreate = (props, callback) ->
  props.created = props.updated = Stamper.stamp()
  props.host_and_id = Credentials.makeKey(props.host, props.id)
  callback null, props
  return

Credentials::beforeUpdate = (props, callback) ->
  props.updated = Stamper.stamp()
  callback null, props
  return

Credentials::beforeSave = (callback) ->
  cred = this
  cred.updated = Stamper.stamp()
  unless cred.host_and_id
    cred.host_and_id = Credentials.makeKey(cred.host, cred.id)
    cred.created = cred.updated
  callback null
  return

Credentials.hostOf = (endpoint) ->
  parts = urlparse(endpoint)
  parts.hostname

Credentials.getFor = (id, endpoint, callback) ->
  host = Credentials.hostOf(endpoint)
  Credentials.getForHostname id, host, callback
  return

Credentials.getForHostname = (id, hostname, callback) ->
  id = ActivityObject.canonicalID(id)
  Step (->
    Credentials.get Credentials.makeKey(hostname, id), this
    return
  ), ((err, cred) ->
    unless err
      
      # if it worked, just return the credentials
      callback null, cred
    else unless err.name is "NoSuchThingError"
      throw err
    else unless Credentials.dialbackClient
      throw new Error("No dialback client for credentials")
    else
      require("./host").Host.ensureHost hostname, this
    return
  ), ((err, host) ->
    throw err  if err
    Credentials.register id, hostname, host.registration_endpoint, this
    return
  ), callback
  return

Credentials.getForHost = (id, host, callback) ->
  id = ActivityObject.canonicalID(id)
  Step (->
    Credentials.get Credentials.makeKey(host.hostname, id), this
    return
  ), ((err, cred) ->
    unless err
      
      # if it worked, just return the credentials
      callback null, cred
    else unless err.name is "NoSuchThingError"
      throw err
    else unless Credentials.dialbackClient
      throw new Error("No dialback client for credentials")
    else
      Credentials.register id, host.hostname, host.registration_endpoint, this
    return
  ), callback
  return

Credentials.register = (id, hostname, endpoint, callback) ->
  Step (->
    toSend = undefined
    body = undefined
    if id.substr(0, 5) is "acct:"
      toSend = id.substr(5)
    else
      toSend = id
    body = querystring.stringify(
      type: "client_associate"
      application_type: "web"
      application_name: toSend
    )
    Credentials.dialbackClient.post endpoint, toSend, body, "application/x-www-form-urlencoded", this
    return
  ), ((err, resp, body) ->
    cred = undefined
    throw err  if err
    throw new Error("HTTP Error " + resp.statusCode + ": " + body)  if resp.statusCode >= 400 and resp.statusCode < 600
    throw new Error("No content type")  unless resp.headers["content-type"]
    throw new Error("Bad content type: " + resp.headers["content-type"])  unless resp.headers["content-type"].substr(0, "application/json".length) is "application/json"
    
    # XXX: make throw a parse error
    cred = new Credentials(JSON.parse(body))
    cred.id = id
    cred.host = hostname
    cred.save this
    return
  ), callback
  return

exports.Credentials = Credentials
