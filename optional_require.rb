module Kernel

  def optional_require(name, &haven)
    begin
      require name
    rescue LoadError
      if haven
        haven.call
      else
        false
      end
    end
  end

end
