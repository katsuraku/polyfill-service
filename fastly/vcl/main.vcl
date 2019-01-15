import querystring;

sub sort_comma_separated_value {
	# This function takes a CSV and tranforms it into a url where each
	# comma-separated-value is a query-string parameter and then uses 
	# Fastly's querystring.sort function to sort the values. Once sorted
	# it then turn the query-parameters back into a CSV.
	# Set the CSV on the header `Sorted-Value`.
	# Returns the sorted CSV on the header `Sorted-Value`.

	# Replace all `&` characters with `^`, this is because `&` would break the value up into pieces.
	set req.http.Sorted-value = regsuball(req.http.Sorted-value, "&", "^");

	# Replace all `,` characters with `&` to break them into individual query values
	# Append `1-` infront of all the query values to make them simpler to transform later
	set req.http.Sorted-value = regsuball(req.http.Sorted-value, ",", "&1-");
	
	# Create a querystring-like string in order for querystring.sort to work.
	set req.http.Sorted-value = querystring.sort("?1-" req.http.Sorted-value);

	# Grab all the query values from the sorted url
	set req.http.Sorted-value = regsub(req.http.Sorted-value, "^\?1-", "");
	
	# Reverse all the previous transformations to get back the single `features` query value value
	set req.http.Sorted-value = regsuball(req.http.Sorted-value, "&1-", ",");
	set req.http.Sorted-value = regsuball(req.http.Sorted-value, "\^", "&");
}

sub normalise_querystring_parameters_for_polyfill_bundle {
	# Store the url without the querystring into a temporary header.
	declare local var.url STRING;
	set var.url = querystring.remove(req.url);

	declare local var.querystring STRING;
	set var.querystring = "?";

	declare local var.callback STRING;
	set var.callback = "";
	# If callback is not set, set to default value ""
	if (req.url.qs ~ "(?i)(?:^|&)callback=([^&#]*)") {
		set var.callback = re.group.1;
	}

	declare local var.compression STRING;
	set var.compression = "";
	# If compression is not set, use the best compression that the user-agent supports.
	if (req.url.qs !~ "(?i)(?:^|&)compression=([^&#]*)") {
		# When Fastly adds Brotli into the Accept-Encoding normalisation we can replace this with: 
		# `set var.querystring = querystring.set(var.querystring, "compression", req.http.Accept-Encoding || "")`

		# Before SP2, IE/6 doesn't always read and cache gzipped content correctly.
		if (req.http.Fastly-Orig-Accept-Encoding && req.http.User-Agent !~ "MSIE 6") {
			if (req.http.Fastly-Orig-Accept-Encoding ~ "br") {
				set var.compression = "br";
			} elsif (req.http.Fastly-Orig-Accept-Encoding ~ "gzip") {
				set var.compression = "gzip";
			} else {
				set var.compression = "";
			}
		} else {
			set var.compression = "";
		}
	} else {
		set var.compression = re.group.1;
	}

	# Remove all querystring parameters which are not part of the public API.
	# set req.url = querystring.regfilter_except(req.url, "^(features|excludes|rum|unknown|flags|version|ua|callback|compression)$");
	
	declare local var.rum STRING;
	set var.rum = "0";
	# If rum is not set, set to default value "0"
	if (req.url.qs ~ "(?i)(?:^|&)rum=([^&#]*)") {
		set var.rum = re.group.1;
	}
	
	declare local var.unknown STRING;
	set var.unknown = "polyfill";
	if (req.url.qs ~ "(?i)(?:^|&)unknown=([^&#]*)") {
		set var.unknown = re.group.1;
	}

	declare local var.flags STRING;
	set var.flags = "";
	if (req.url.qs ~ "(?i)(?:^|&)flags=([^&#]*)") {
		set var.flags = re.group.1;
	}

	# If version is not set, set to default value ""
	declare local var.version STRING;
	set var.version = "";
	if (req.url.qs ~ "(?i)(?:^|&)version=([^&#]*)") {
		set var.version = re.group.1;
	}
	
	# If ua is not set, normalise the User-Agent header based upon the version of the polyfill-library that has been requested.
	declare local var.ua STRING;
	set var.ua = "";
	if (req.url.qs !~ "(?i)(?:^|&)ua=([^&#]*)") {
		if (req.url.qs ~ "(?i)(?:^|&)version=3\.25\.1(&|$)") {
			call normalise_user_agent_3_25_1;
		} else {
			call normalise_user_agent_latest;
		}
		set var.ua = req.http.Normalized-User-Agent;
	} else {
		set var.ua = re.group.1;
	}

	
	declare local var.excludes STRING;
	set var.excludes = "";
	if (req.url.qs ~ "(?i)(?:^|&)excludes=([^&#]*)") {
		# We add the value of the excludes parameter to this header
		# This is to be able to have sort_comma_separated_value sort the value
		set req.http.Sorted-value = urldecode(re.group.1);
		call sort_comma_separated_value;
		set var.excludes = req.http.Sorted-Value;
	}

	declare local var.features STRING;
	set var.features = "default";
	if (req.url.qs ~ "(?i)(?:^|&)features=([^&#]*)") {
		# We add the value of the features parameter to this header
		# This is to be able to have sort_comma_separated_value sort the value
		set req.http.Sorted-value = urldecode(re.group.1);
		call sort_comma_separated_value;
		# The header Sorted-Value now contains the sorted version of the features parameter.
		set var.features = req.http.Sorted-Value;
	}

	set req.url = var.url "?callback=" var.callback + "&compression=" var.compression+ "&excludes=" var.excludes+ "&features=" var.features+ "&rum=" var.rum+ "&ua=" var.ua+ "&unknown=" var.unknown+ "&version=" var.version;
}

include "ua_parser.vcl";
include "normalise-user-agent-3-25-1.vcl";
include "normalise-user-agent-latest.vcl";

# The Fastly VCL boilerplate.
include "fastly-boilerplate-begin.vcl";

include "breadcrumbs.vcl";
include "redirects.vcl";
include "synthetic-responses.vcl";
include "polyfill-service.vcl";

# Finally include the last bit of VCL, this _must_ be last!
include "fastly-boilerplate-end.vcl";
