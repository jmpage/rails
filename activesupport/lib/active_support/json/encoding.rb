require 'active_support/core_ext/object/json'
require 'active_support/core_ext/module/delegation'
require 'active_support/json/variable'

require 'bigdecimal'
require 'active_support/core_ext/big_decimal/conversions' # for #to_s
require 'active_support/core_ext/hash/except'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/object/instance_variables'
require 'time'
require 'active_support/core_ext/time/conversions'
require 'active_support/core_ext/date_time/conversions'
require 'active_support/core_ext/date/conversions'
require 'set'

module ActiveSupport
  class << self
    delegate :use_standard_json_time_format, :use_standard_json_time_format=,
      :escape_html_entities_in_json, :escape_html_entities_in_json=,
      :json_encoder, :json_encoder=,
      :to => :'ActiveSupport::JSON::Encoding'
  end

  module JSON
    # matches YAML-formatted dates
    DATE_REGEX = /^(?:\d{4}-\d{2}-\d{2}|\d{4}-\d{1,2}-\d{1,2}[T \t]+\d{1,2}:\d{2}:\d{2}(\.[0-9]*)?(([ \t]*)Z|[-+]\d{2}?(:\d{2})?))$/

    # Dumps objects in JSON (JavaScript Object Notation).
    # See www.json.org for more info.
    #
    #   ActiveSupport::JSON.encode({ team: 'rails', players: '36' })
    #   # => "{\"team\":\"rails\",\"players\":\"36\"}"
    def self.encode(value, options = nil)
      Encoding.json_encoder.new(options).encode(value)
    end

    module Encoding #:nodoc:
      class JSONGemEncoder #:nodoc:
        attr_reader :options

        def initialize(options = nil)
          @options = options || {}
          @seen = Set.new
        end

        # Encode the given object into a JSON string
        def encode(value)
          stringify jsonify value.as_json(options.dup)
        end

        private
          # Rails does more escaping than the JSON gem natively does (we
          # escape \u2028 and \u2029 and optionally >, <, & to work around
          # certain browser problems).
          ESCAPED_CHARS = {
            "\u2028" => '\u2028',
            "\u2029" => '\u2029',
            '>'      => '\u003e',
            '<'      => '\u003c',
            '&'      => '\u0026',
            }

          ESCAPE_REGEX_WITH_HTML_ENTITIES = /[\u2028\u2029><&]/u
          ESCAPE_REGEX_WITHOUT_HTML_ENTITIES = /[\u2028\u2029]/u

          # This class wraps all the strings we see and does the extra escaping
          class EscapedString < String
            def to_json(*)
              if Encoding.escape_html_entities_in_json
                super.gsub ESCAPE_REGEX_WITH_HTML_ENTITIES, ESCAPED_CHARS
              else
                super.gsub ESCAPE_REGEX_WITHOUT_HTML_ENTITIES, ESCAPED_CHARS
              end
            end
          end

          # Mark these as private so we don't leak encoding-specific constructs
          private_constant :ESCAPED_CHARS, :ESCAPE_REGEX_WITH_HTML_ENTITIES, 
            :ESCAPE_REGEX_WITHOUT_HTML_ENTITIES, :EscapedString

          # Recursively turn the given object into a "jsonified" Ruby data structure
          # that the JSON gem understands - i.e. we want only Hash, Array, String,
          # Numeric, true, false and nil in the final tree. Calls #as_json on it if
          # it's not from one of these base types.
          # 
          # This allows developers to implement #as_json withouth having to worry
          # about what base types of objects they are allowed to return and having
          # to remember calling #as_json recursively.
          # 
          # By default, the options hash is not passed to the children data structures
          # to avoid undesiarable result. Develoers must opt-in by implementing
          # custom #as_json methods (e.g. Hash#as_json and Array#as_json).
          def jsonify(value)
            if value.is_a?(Hash)
              Hash[value.map { |k, v| [jsonify(k), jsonify(v)] }]
            elsif value.is_a?(Array)
              value.map { |v| jsonify(v) }
            elsif value.is_a?(String)
              EscapedString.new(value)
            elsif value.is_a?(Numeric)
              value
            elsif value == true
              true
            elsif value == false
              false
            elsif value == nil
              nil
            else
              jsonify value.as_json
            end
          end

          # Encode a "jsonified" Ruby data structure using the JSON gem
          def stringify(jsonified)
            ::JSON.generate(jsonified, quirks_mode: true, max_nesting: false)
          end
      end

      class << self
        # If true, use ISO 8601 format for dates and times. Otherwise, fall back
        # to the Active Support legacy format.
        attr_accessor :use_standard_json_time_format

        # If true, encode >, <, & as escaped unicode sequences (e.g. > as \u003e)
        # as a safety measure.
        attr_accessor :escape_html_entities_in_json

        # Sets the encoder used by Rails to encode Ruby objects into JSON strings
        # in +Object#to_json+ and +ActiveSupport::JSON.encode+.
        attr_accessor :json_encoder

        # Deprecate CircularReferenceError
        def const_missing(name)
          if name == :CircularReferenceError
            message = "The JSON encoder in Rails 4.1 no longer offers protection from circular references. " \
                      "You are seeing this warning because you are rescuing from (or otherwise referencing) " \
                      "ActiveSupport::Encoding::CircularReferenceError. In the future, this error will be " \
                      "removed from Rails. You should remove these rescue blocks from your code and ensure " \
                      "that your data structures are free of circular references so they can be properly " \
                      "serialized into JSON.\n\n" \
                      "For example, the following Hash contains a circular reference to itself:\n" \
                      "   h = {}\n" \
                      "   h['circular'] = h\n" \
                      "In this case, calling h.to_json would not work properly."

            ActiveSupport::Deprecation.warn message

            SystemStackError
          else
            super
          end
        end
      end

      self.use_standard_json_time_format = true
      self.escape_html_entities_in_json  = true
      self.json_encoder = JSONGemEncoder
    end
  end
end

class Object
  def as_json(options = nil) #:nodoc:
    if respond_to?(:to_hash)
      to_hash
    else
      instance_values
    end
  end
end

class Struct #:nodoc:
  def as_json(options = nil)
    Hash[members.zip(values)]
  end
end

class TrueClass
  def as_json(options = nil) #:nodoc:
    self
  end

  def encode_json(encoder) #:nodoc:
    to_s
  end
end

class FalseClass
  def as_json(options = nil) #:nodoc:
    self
  end

  def encode_json(encoder) #:nodoc:
    to_s
  end
end

class NilClass
  def as_json(options = nil) #:nodoc:
    self
  end

  def encode_json(encoder) #:nodoc:
    'null'
  end
end

class String
  def as_json(options = nil) #:nodoc:
    self
  end

  def encode_json(encoder) #:nodoc:
    encoder.escape(self)
  end
end

class Symbol
  def as_json(options = nil) #:nodoc:
    to_s
  end
end

class Numeric
  def as_json(options = nil) #:nodoc:
    self
  end

  def encode_json(encoder) #:nodoc:
    to_s
  end
end

class Float
  # Encoding Infinity or NaN to JSON should return "null". The default returns
  # "Infinity" or "NaN" which breaks parsing the JSON. E.g. JSON.parse('[NaN]').
  def as_json(options = nil) #:nodoc:
    finite? ? self : nil
  end
end

class BigDecimal
  # A BigDecimal would be naturally represented as a JSON number. Most libraries,
  # however, parse non-integer JSON numbers directly as floats. Clients using
  # those libraries would get in general a wrong number and no way to recover
  # other than manually inspecting the string with the JSON code itself.
  #
  # That's why a JSON string is returned. The JSON literal is not numeric, but
  # if the other end knows by contract that the data is supposed to be a
  # BigDecimal, it still has the chance to post-process the string and get the
  # real value.
  #
  # Use <tt>ActiveSupport.use_standard_json_big_decimal_format = true</tt> to
  # override this behavior.
  def as_json(options = nil) #:nodoc:
    if finite?
      ActiveSupport.encode_big_decimal_as_string ? to_s : self
    else
      nil
    end
  end
end

class Regexp
  def as_json(options = nil) #:nodoc:
    to_s
  end
end

module Enumerable
  def as_json(options = nil) #:nodoc:
    to_a.as_json(options)
  end
end

class Range
  def as_json(options = nil) #:nodoc:
    to_s
  end
end

class Array
  def as_json(options = nil) #:nodoc:
    # use encoder as a proxy to call as_json on all elements, to protect from circular references
    encoder = options && options[:encoder] || ActiveSupport::JSON::Encoding::Encoder.new(options)
    map { |v| encoder.as_json(v, options) }
  end

  def encode_json(encoder) #:nodoc:
    # we assume here that the encoder has already run as_json on self and the elements, so we run encode_json directly
    "[#{map { |v| v.encode_json(encoder) } * ','}]"
  end
end

class Hash
  def as_json(options = nil) #:nodoc:
    # create a subset of the hash by applying :only or :except
    subset = if options
      if attrs = options[:only]
        slice(*Array(attrs))
      elsif attrs = options[:except]
        except(*Array(attrs))
      else
        self
      end
    else
      self
    end

    # use encoder as a proxy to call as_json on all values in the subset, to protect from circular references
    encoder = options && options[:encoder] || ActiveSupport::JSON::Encoding::Encoder.new(options)
    Hash[subset.map { |k, v| [k.to_s, encoder.as_json(v, options)] }]
  end

  def encode_json(encoder) #:nodoc:
    # values are encoded with use_options = false, because we don't want hash representations from ActiveModel to be
    # processed once again with as_json with options, as this could cause unexpected results (i.e. missing fields);

    # on the other hand, we need to run as_json on the elements, because the model representation may contain fields
    # like Time/Date in their original (not jsonified) form, etc.

    "{#{map { |k,v| "#{encoder.encode(k.to_s)}:#{encoder.encode(v, false)}" } * ','}}"
  end
end

class Time
  def as_json(options = nil) #:nodoc:
    if ActiveSupport.use_standard_json_time_format
      xmlschema
    else
      %(#{strftime("%Y/%m/%d %H:%M:%S")} #{formatted_offset(false)})
    end
  end
end

class Date
  def as_json(options = nil) #:nodoc:
    if ActiveSupport.use_standard_json_time_format
      strftime("%Y-%m-%d")
    else
      strftime("%Y/%m/%d")
    end
  end
end

class DateTime
  def as_json(options = nil) #:nodoc:
    if ActiveSupport.use_standard_json_time_format
      xmlschema
    else
      strftime('%Y/%m/%d %H:%M:%S %z')
    end
  end
end
