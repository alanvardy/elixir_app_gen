defmodule AppGen.ProjectGenerator do
  def inject_into_file!(path, inject_msg \\ "", func) do
    contents = path |> File.read! |> func.()

    if not File.exists?(path) or File.read!(path) !== contents do
      IO.puts(IO.ANSI.format([
        :green, "* injecting #{pad_inject_message(inject_msg)}", :reset, path
      ]))

      File.write!(path, contents)
    end
  end

  defp pad_inject_message(inject_msg) do
    if inject_msg !== "" and not String.ends_with?(inject_msg, " ") do
      "#{inject_msg} "
    else
      inject_msg
    end
  end
end
