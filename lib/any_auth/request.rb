# frozen_string_literal: true

module AnyAuth
  Request = Data.define(:url, :session) do
    def inspect
      "#<data #{self.class.name} url=#{url.inspect}>"
    end

    def pretty_print(printer)
      printer.text(inspect)
    end
  end
end
