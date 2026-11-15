# frozen_string_literal: true

module AnyAuth
  Request = Data.define(:url, :session) do
    def inspect
      "#<data #{self.class.name} url=#{url.inspect}>"
    end

    def pretty_print(printer)
      printer.text(inspect)
    end

    def as_json(*)
      to_h.except(:session).as_json
    end
  end
end
