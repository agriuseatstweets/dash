def _extract_entity(event, from, get_out, prefix)
  arr = event.get("#{prefix}[entities][#{from}]")
  return unless arr

  extracted = arr.map{ |h| h["#{get_out}"] }
  event.set("#{prefix}[entities][#{from}]", extracted)
end

def _set_from(event, to, from)
  event.set(to, event.get(from))
end

def _handle_truncated(event, prefix = nil)
  truncated = event.get("#{prefix}[truncated]")
  if truncated
    _set_from(event, "#{prefix}[entities]", "#{prefix}[extended_tweet][entities]")
    _set_from(event, "#{prefix}[text]", "#{prefix}[extended_tweet][full_text]")
  end
end

def _handle_entities(event, prefix = nil)
  _extract_entity(event, "user_mentions", "screen_name", prefix)
  _extract_entity(event, "hashtags", "text", prefix)
  _extract_entity(event, "urls", "expanded_url", prefix)
  _extract_entity(event, "media", "media_url", prefix)
end

def _trim_subtweet(event, subkey, keys)
  s = event.get(subkey)
  s["user"] = s["user"].slice("screen_name")
  event.set(subkey, s.slice(*keys))
end

def _clean_user(event)
  user = event.get("user")
  return unless user
  keys = user.keys().select{ |k| !k.include? "profile" }
  event.set("user", user.slice(*keys))
end

def filter(event)
  if !event.get("[limit][track]").nil?
    event.tag("limit")
    return [event]
  end

  if !event.get("delete").nil?
    event.tag("delete")
    return [event]
  end

  event.tag("tweet")

  # retweets - collect into top level
  if event.get("retweeted_status")
    ["entities", "truncated", "extended_tweet"].each do |e|
      _set_from(event, e, "[retweeted_status][#{e}]")
    end
    _trim_subtweet(event, "retweeted_status", ["user", "id_str", "created_at"])
  end

  # quote tweets -> keep entities separate... TODO: get extended tweet from quoted_status!
  if event.get("quoted_status")
    _handle_truncated(event, "[quoted_status]")
    _handle_entities(event, "[quoted_status]")
    _trim_subtweet(event, "quoted_status", ["user", "id_str", "entities", "text", "created_at"])
  end

  # handle truncated values & entities
  _handle_truncated(event)
  _handle_entities(event)
  event.remove("extended_tweet")

  # clean user
  _clean_user(event)

  [event]
end

test "user: profile fields dropped" do
  in_event {{ "user" => { "id" => 123, "lang" => "en", "profile_banner_url" => "foo"}}}
  expect("banner url is gone") {|events| events.first.get("[user][profile_banner_url]").nil?}
  expect("everything else still there") {|events| events.first.get("[user][lang]") == "en"}
end

test "when limit exists" do
  in_event { { "limit" => { "track" => 1235 } } }
  expect("is tagged") {|events|  events.first.get("tags").include?("limit")}
end

test "user mentions flattened" do
  in_event { {"user" => {}, "entities" => { "user_mentions" => [{"screen_name" => "foo"}, {"screen_name" => "bar"}] } } }
  expect("only names in user_mentions") {|events|  events.first.get("[entities][user_mentions]") == ["foo", "bar"]}
  expect("no hashtags") {|events|  events.first.get("[entities][hashtags]").nil?}
end

test "hashtags flattend" do
  in_event { { "user" => {}, "entities" => { "hashtags" => [{"text" => "foo"}, {"text" => "bar"}] } } }
  expect("only names in hash tags") do |events|
    events.first.get("[entities][hashtags]") == ["foo", "bar"]
  end
  expect("no user mentions") do |events|
    events.first.get("[entities][user_mentions]").nil?
  end
end

test "flattening works with extended values" do
  in_event { {
               "user" => {},
               "truncated" => true,
               "text" => "foo",
               "entities" => {"hashtags" => [{"text": "foo"}]},
               "extended_tweet" => { "full_text" => "foobar",
                                     "entities" => { "hashtags" => [{"text" => "foo"}, {"text" => "bar"}]}}
             }}
  expect("user mentions from extended") do |events|
    events.first.get("[entities][hashtags]") == ["foo", "bar"]
  end
  expect("fulltext from extended") do |events|
    events.first.get("text") == "foobar"
  end
end


test "retweeted status" do
  in_event { {
               "user" => {},
               "truncated" => true,
               "text" => "foo",
               "entities" => {"hashtags" => [{"text": "foo"}]},
               "extended_tweet" => {
                 "full_text" => "foobar",
                 "entities" => { "hashtags" => [{"text" => "foo"}, {"text" => "bar"}]}
               },
               "retweeted_status" => {
                 "user" => { "screen_name" => "matt", "nope" => "gone" },
                 "truncated" => true,
                 "created_at" => "Mon Apr 17 13:53:38 +0000 2017",
                 "id_str" => "123",
                 "entities" => {"hashtags" => [{"text": "foo"}]},
                 "extended_tweet" => {
                   "full_text" => "foobarbaz",
                   "entities" => { "hashtags" => [{"text" => "foo"}, {"text" => "bar"}, {"text" => "qux"}]}
                 }
               }
             } }
  expect("entities from retweet") do |events|
    events.first.get("[entities][hashtags]") == ["foo", "bar", "qux"]
  end
  expect("fulltext from extended retweet") do |events|
    events.first.get("text") == "foobarbaz"
  end
  expect("user screenname is preserved") do |events|
    events.first.get("[retweeted_status][user][screen_name]") == "matt"
  end
  expect("user screenname is the only thing there") do |events|
    events.first.get("[retweeted_stats][user][nope]").nil?
  end
end


test "quoted status" do
  in_event { {
               "truncated" => true,
               "user" => { "screen_name": "max" },
               "text" => "foo",
               "entities" => {"hashtags" => [{"text": "foo"}]},
               "extended_tweet" => {
                 "full_text" => "foobar",
                 "entities" => { "hashtags" => [{"text" => "foo"}, {"text" => "bar"}]}
               },
               "quoted_status" => {
                 "user" => { "screen_name" => "matt", "nope" => "gone" },
                 "created_at" => "Mon Apr 17 13:53:38 +0000 2017",
                 "truncated" => true,
                 "id_str" => "123",
                 "entities" => {"hashtags" => [{"text": "foo"}]},
                 "extended_tweet" => {
                   "full_text" => "foobarbaz",
                   "entities" => { "hashtags" => [{"text" => "foo"}, {"text" => "bar"}, {"text" => "qux"}]}
                 }
               }
             } }

  expect("entities from quoted_status") do |events|
    events.first.get("[quoted_status][entities][hashtags]") == ["foo", "bar", "qux"]
  end
  expect("entities from status") do |events|
    events.first.get("[entities][hashtags]") == ["foo", "bar"]
  end
  expect("fulltext from from quoted_status") do |events|
    events.first.get("[quoted_status][text]") == "foobarbaz"
  end
  expect("fulltext from from extended_tweet still") do |events|
    events.first.get("[text]") == "foobar"
  end
  expect("user screenname is preserved") do |events|
    events.first.get("[user][screen_name]") == "max"
  end
end
