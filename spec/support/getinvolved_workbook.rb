require "zip"
require "cgi"

# Small, anonymous Excel fixtures with the same headers and blank-cell layout as GetInvolved.
module GetinvolvedWorkbook
     def getinvolved_workbook(rows, headers: GetinvolvedEventImport::HEADERS, sheets: 1)
          sheet_rows = [ headers, *rows ].each_with_index.map do |row, index|
               cells = row.each_with_index.filter_map do |value, column|
                    next if value.nil?

                    reference = "#{(65 + column).chr}#{index + 1}"
                    if value.is_a?(DateTime)
                         serial = (value - DateTime.new(1899, 12, 30)).to_f
                         %(<c r="#{reference}" s="1"><v>#{serial}</v></c>)
                    else
                         %(<c r="#{reference}" t="inlineStr"><is><t xml:space="preserve">#{CGI.escapeHTML(value.to_s)}</t></is></c>)
                    end
               end.join
               %(<row r="#{index + 1}">#{cells}</row>)
          end.join
          entries = {
            "[Content_Types].xml" => '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>',
            "_rels/.rels" => '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
            "xl/workbook.xml" => %(<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>#{(1..sheets).map { |i| %(<sheet name="Events #{i}" sheetId="#{i}" r:id="rId#{i}"/>) }.join}</sheets></workbook>),
            "xl/_rels/workbook.xml.rels" => %(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{(1..sheets).map { |i| %(<Relationship Id="rId#{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet#{i}.xml"/>) }.join}</Relationships>),
            "xl/styles.xml" => '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="22"/></cellXfs></styleSheet>'
          }
          (1..sheets).each do |i|
               entries["xl/worksheets/sheet#{i}.xml"] = %(<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{sheet_rows}</sheetData></worksheet>)
          end
          Zip::OutputStream.write_buffer do |archive|
               entries.each do |name, xml|
                    archive.put_next_entry(name)
                    archive.write(xml)
               end
          end.string
     end
end

RSpec.configure do |config|
     config.include GetinvolvedWorkbook
end
