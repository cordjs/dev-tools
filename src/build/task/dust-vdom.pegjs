start
  = body

/*-------------------------------------------------------------------------------------------------------------------------------------
   body is defined as anything that matches with the part 0 or more times
---------------------------------------------------------------------------------------------------------------------------------------*/
body
  = p:part* {
    return p.filter(function(x){return x != null;});
    // return ["body"]
    //        .concat(p.filter(function(x){return x != null;}))
    //        .concat([line(), column()]);
  }

/*-------------------------------------------------------------------------------------------------------------------------------------
   part is defined as anything that matches with raw or comment or section or partial or special or reference or buffer
---------------------------------------------------------------------------------------------------------------------------------------*/
part
  = html_tag / eol / plain_text / js_expr //raw / comment / section / partial / special / reference / buffer

html_tag
  = s:html_tag_start b:body e:html_tag_end? &{
    if( (!e) || (s !== e) ) {
      error("Expected end tag for "+s+" but it was not found.");
    }
    return true;
  }
  {
    return {
      type: 'html_tag',
      name: e,
      contents: b,
      line: line(),
      column: column()
    };
    // return ['html_tag', e, b, [line(), column()]]
  }

html_tag_start
  = lt n:key gt { return n; }

html_tag_end
  = lt '/' n:key gt { return n; }

/*-------------------------------------------------------------------------------------------------------------------------------------
   key is defined as a character matching a to z, upper or lower case, followed by 0 or more alphanumeric characters
---------------------------------------------------------------------------------------------------------------------------------------*/
key "key"
  = h:[a-zA-Z_$] t:[0-9a-zA-Z_$-]*
  { return h + t.join(''); }

js_expr "Javascript Expression"
  = ld e:(!rd c:. {return c})+ rd
  {
    return {
      type: 'expr',
      code: e.join(''),
      line: line(),
      column: column()
    };
  }


plain_text "plain text as is"
  = b:(!any_tag !js_expr c:. {return c})+
  {
    return {
      type: 'text',
      text: b.join(''),
      line: line(),
      column: column()
    };
  }

any_tag
  = lt ws* '/'? ws* (!gt !eol .)+ ws* gt

lt
  = '<'

gt
  = '>'

ld
  = "{"

rd
  = "}"

eol
  = "\n"     { return undefined; }   //line feed
  / "\r\n"   { return undefined; }   //carriage + line feed
  / "\r"     { return undefined; }   //carriage return
  / "\u2028" { return undefined; }   //line separator
  / "\u2029" { return undefined; }   //paragraph separator

ws
  = [\t\v\f \u00A0\uFEFF] { return undefined; }
  / eol { return undefined; }
