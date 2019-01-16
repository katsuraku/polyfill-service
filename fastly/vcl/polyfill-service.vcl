sub set_backend {
	# Calculate the ideal region to route the request to.
	declare local var.region STRING;
	if (server.region ~ "(APAC|Asia|North-America|South-America|US-Central|US-East|US-West)") {
		set var.region = "US";
	} else {
		set var.region = "EU";
	}

	# Gather the health of the shields and origins.
	declare local var.v3_eu_is_healthy BOOL;
	set req.backend = F_v3_eu;
	set var.v3_eu_is_healthy = req.backend.healthy;

	declare local var.v3_us_is_healthy BOOL;
	set req.backend = F_v3_us;
	set var.v3_us_is_healthy = req.backend.healthy;

	# Set some sort of default, that shouldn't get used.
	set req.backend = F_v3_eu;

	# Route EU requests to the nearest healthy shield or origin.
	if (var.region == "EU") {
		if (var.v3_eu_is_healthy) {
			set req.backend = F_v3_eu;
		} elseif (var.v3_us_is_healthy) {
			set req.backend = F_v3_us;
		} else {
			# Everything is on fire... but lets try the origin anyway just in case
			# it's the probes that are wrong
			# set req.backend = F_origin_last_ditch_eu;
		}
	}

	# Route US requests to the nearest healthy shield or origin.
	if (var.region == "US") {
		if (var.v3_us_is_healthy) {
			set req.backend = F_v3_us;
		} elseif (var.v3_eu_is_healthy) {
			set req.backend = F_v3_eu;
		} else {
			# Everything is on fire... but lets try the origin anyway just in case
			# it's the probes that are wrong
			# set req.backend = F_origin_last_ditch_us;
		}
	}

	# Persist the decision so we can debug the result.
	set req.http.Debug-Backend = req.backend;

	# The Fastly macro is inserted after the backend is selected because the
	# macro has the code to select the correct req.http.Host value based on the backend.
	#FASTLY recv
}

sub vcl_recv {
	if (req.http.Fastly-Debug) {
		call breadcrumb_recv;
	}

	if (req.method != "GET" && req.method != "HEAD" && req.method != "OPTIONS" && req.method != "FASTLYPURGE" && req.method != "PURGE") {
		error 911;
	}

	if (req.method == "OPTIONS") {
		error 912;
	}

	# Override the v3 defaults with the defaults of v2
	if (req.url ~ "^/v2/polyfill(\.min)?\.js") {
		set req.url = regsub(req.url, "^/v2", "/v3");
		set req.url = querystring.set(req.url, "version", "3.25.1");
		declare local var.unknown STRING;
		set var.unknown = subfield(req.url.qs, "unknown", "&");
		set req.url = querystring.set(req.url, "unknown", if(var.unknown != "", var.unknown, "ignore"));
	}

	if (req.url ~ "^/v3/polyfill(\.min)?\.js") {
		call normalise_querystring_parameters_for_polyfill_bundle;
	} else {
		# Sort the querystring parameters alphabetically to improve chances of hitting a cached copy.
		# If querystring is empty, remove the ? from the url.
		set req.url = querystring.clean(querystring.sort(req.url));
	}
	call set_backend;
}

sub vcl_hash {
	if (req.http.Fastly-Debug) {
		call breadcrumb_hash;
	}

	# We are not adding req.http.host to the hash because we want https://cdn.polyfill.io and https://polyfill.io to be a single object in the cache.
	# set req.hash += req.http.host;
	set req.hash += req.url;
	# We include return(hash) to stop the function falling through to the default VCL built into varnish, which for vcl_hash will add req.url and req.http.Host to the hash.
	return(hash);
}

sub vcl_miss {
	if (req.http.Fastly-Debug) {
		call breadcrumb_miss;
	}
}

sub vcl_pass {
	if (req.http.Fastly-Debug) {
		call breadcrumb_pass;
	}
}

sub unset_common_request_headers {
	# Common request headers from https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#Standard_request_fields
	unset bereq.http.A-IM;

	# These may be needed by the backend to decide what type of response to return
	# unset bereq.http.Accept;
	# unset bereq.http.Accept-Charset;
	unset bereq.http.Accept-Encoding;
	# unset bereq.http.Accept-Language;
	unset bereq.http.Accept-Datetime;
	# Needed if the backend is meant to handle CORS (Cross Origin Resource Sharing)
	# unset bereq.http.Access-Control-Request-Method;
	# unset bereq.http.Access-Control-Request-Headers;
	unset bereq.http.Authorization;
	unset bereq.http.Cache-Control;
	unset bereq.http.Connection;
	# Variable `bereq.http.Content-Length` cannot be unset
	# unset bereq.http.Content-Length;
	unset bereq.http.Content-MD5;
	unset bereq.http.Content-Type;
	unset bereq.http.Cookie;
	unset bereq.http.Date;
	# Variable `bereq.http.Expect` cannot be unset
	# unset bereq.http.Expect;
	unset bereq.http.Forwarded;
	unset bereq.http.From;
	# Needed for Heroku
	# unset bereq.http.Host;
	unset bereq.http.HTTP2-Settings;
	# These are needed to enable the backend to return 304 not modified
	# unset bereq.http.If-Match;
	# unset bereq.http.If-Modified-Since;
	# unset bereq.http.If-None-Match;
	# unset bereq.http.If-Range;
	# unset bereq.http.If-Unmodified-Since;
	unset bereq.http.Max-Forwards;
	# Needed if the backend is meant to handle CORS (Cross Origin Resource Sharing)
	# unset bereq.http.Origin;
	unset bereq.http.Pragma;
	# Variable `bereq.http.Proxy-Authorization` cannot be unset
	# unset bereq.http.Proxy-Authorization;
	unset bereq.http.Range;
	unset bereq.http.Referer;
	# Variable `bereq.http.TE` cannot be unset
	# unset bereq.http.TE;
	unset bereq.http.User-Agent;
	unset bereq.http.Upgrade;
	unset bereq.http.Via;
	unset bereq.http.Warning;
	
	# common request headers from https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#Common_non-standard_request_fields
	unset bereq.http.Upgrade-Insecure-Requests;
	unset bereq.http.X-Requested-With;
	unset bereq.http.DNT;
	unset bereq.http.X-Forwarded-For;
	unset bereq.http.X-Forwarded-Host;
	unset bereq.http.X-Forwarded-Proto;
	unset bereq.http.Front-End-Https;
	unset bereq.http.X-Http-Method-Override;
	unset bereq.http.X-ATT-DeviceId;
	unset bereq.http.X-Wap-Profile;
	unset bereq.http.Proxy-Connection;
	unset bereq.http.X-UIDH;
	unset bereq.http.X-Csrf-Token;
	# unset bereq.http.X-Request-ID;
	unset bereq.http.X-Correlation-ID;
	unset bereq.http.Save-Data;

	# Fastly specific headers
	unset bereq.http.Fastly-Orig-Accept-Encoding;
	unset bereq.http.Fastly-Tmp-Obj-TTL;
  	unset bereq.http.Fastly-Tmp-Obj-Grace;
	unset bereq.http.Fastly-Cachetype;
	unset bereq.http.Surrogate-Key;
  	unset bereq.http.Surrogate-Control;
	unset bereq.http.Fastly-FF;

	# polyfill-service specific headers
	unset bereq.http.Sorted-Value;
	unset bereq.http.useragent_parser_family;
	unset bereq.http.useragent_parser_major;
	unset bereq.http.useragent_parser_minor;
	unset bereq.http.useragent_parser_patch;
	unset bereq.http.normalized_user_agent_family;
	unset bereq.http.normalized_user_agent_major_version;
	unset bereq.http.normalized_user_agent_minor_version;
	unset bereq.http.normalized_user_agent_patch_version;
	unset bereq.http.Normalized-User-Agent;
	unset bereq.http.Orig-URL;
	unset bereq.http.Fastly-Purge-Requires-Auth;
	unset bereq.http.X-VCL-Route;
	unset bereq.http.X-PreFetch-Miss;
	unset bereq.http.X-PreFetch-Pass;
	unset bereq.http.Debug-Backend;
	unset bereq.http.X-Timer;
	unset bereq.http.Fastly-Force-Shield;
}

sub vcl_fetch {
	if (req.http.Fastly-Debug) {
		call breadcrumb_fetch;
	}

	call unset_common_request_headers;

	# These header are only required for HTML documents.
	if (beresp.http.Content-Type ~ "text/html") {
		# Enables the cross-site scripting filter built into most modern web browsers.
		set beresp.http.X-XSS-Protection = "1; mode=block";	

		# Allow only content from the site's own origin (this excludes subdomains) and www.ft.com.
		# Don't allow the website to be used within an iframe
		if (!beresp.http.Content-Security-Policy) {
			set beresp.http.Content-Security-Policy = "default-src 'self'; font-src 'self' https://www.ft.com; img-src 'self' https://www.ft.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
		}
	}
	# Prevents MIME-sniffing a response away from the declared content type.
	set beresp.http.X-Content-Type-Options = "nosniff";

	# Ensure the site is only served over HTTPS and reduce the chances of someone performing a MITM attack.
	set beresp.http.Strict-Transport-Security = "max-age=31536000; includeSubdomains; preload";

	# The Referrer-Policy header governs which referrer information, sent in the Referer header, should be included with requests made.
	# Send a full URL when performing a same-origin request, but only send the origin of the document for other cases.
	set beresp.http.Referrer-Policy = "origin-when-cross-origin";

	# Enable purging of all objects in the Fastly cache by issuing a purge with the key "polyfill-service".
	if (beresp.http.Surrogate-Key !~ "\bpolyfill-service\b") {
		set beresp.http.Surrogate-Key = if(beresp.http.Surrogate-Key, beresp.http.Surrogate-Key " polyfill-service", "polyfill-service");
	}

	set beresp.http.Timing-Allow-Origin = "*";

	if (req.http.Normalized-User-Agent) {
		set beresp.http.Normalized-User-Agent = req.http.Normalized-User-Agent;
		set beresp.http.Detected-User-Agent = req.http.useragent_parser_family "/"  req.http.useragent_parser_major "." req.http.useragent_parser_minor "." req.http.useragent_parser_patch;
	}
}

sub vcl_deliver {
	if (req.http.Fastly-Debug) {
		call breadcrumb_deliver;
	}

	set req.http.Fastly-Force-Shield = "yes";

	# Allow cross origin GET, HEAD, and OPTIONS requests to be made.
	if (req.http.Origin) {
		set resp.http.Access-Control-Allow-Origin = "*";
		set resp.http.Access-Control-Allow-Methods = "GET,HEAD,OPTIONS";
	}

	if (req.url ~ "^/v3/polyfill(\.min)?\.js") {
		# Need to add "Vary: User-Agent" in after vcl_fetch to avoid the 
		# "Vary: User-Agent" entering the Varnish cache.
		# We need "Vary: User-Agent" in the browser cache because a browser
		# may update itself to a version which needs different polyfills
		# So we need to have it ignore the browser cached bundle when the user-agent changes.
		add resp.http.Vary = "User-Agent";
		add resp.http.Vary = "Accept-Encoding";
	}

	add resp.http.Server-Timing = fastly_info.state {", fastly;desc="Edge time";dur="} time.elapsed.msec;

	if (req.http.Fastly-Debug) {
		set resp.http.Debug-Backend = req.http.Debug-Backend;
		set resp.http.Debug-Host = req.http.Host;
		set resp.http.Debug-Fastly-Restarts = req.restarts;
		set resp.http.Debug-Orig-URL = req.http.Orig-URL;
		set resp.http.Debug-VCL-Route = req.http.X-VCL-Route;
		set resp.http.useragent_parser_family = req.http.useragent_parser_family;
		set resp.http.useragent_parser_major = req.http.useragent_parser_major;
		set resp.http.useragent_parser_minor = req.http.useragent_parser_minor;
		set resp.http.useragent_parser_patch = req.http.useragent_parser_patch;
	} else {
		unset resp.http.Server;
		unset resp.http.Via;
		unset resp.http.X-Cache;
		unset resp.http.X-Cache-Hits;
		unset resp.http.X-Served-By;
		unset resp.http.X-Timer;
		unset resp.http.Fastly-Restarts;
	}
}

sub vcl_error {
	if (obj.status == 911) {
		set obj.status = 405;
		set obj.response = "METHOD NOT ALLOWED";
		set obj.http.Content-Type = "text/html; charset=utf-8";
		set obj.http.Cache-Control = "private, no-store";
		synthetic req.method " METHOD NOT ALLOWED";
		return (deliver);
	}
	if (obj.status == 912) {
		set obj.status = 200;
		set obj.response = "OK";
		set obj.http.Allow = "OPTIONS, GET, HEAD";
		return (deliver);
	}
}
