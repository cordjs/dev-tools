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
  = s:html_tag_start gt b:body e:html_end_tag? &{
    console.log("html_tag", s, b, e);
    if( (!e) || (s.name !== e) ) {
      error("Expected end tag for "+s.name+" but it was not found.");
    }
    return true;
  }
  {
    return {
      type: 'html_tag',
      name: e,
      contents: b,
      props: s.props,
      line: line(),
      column: column()
    };
  }
  / s:html_tag_start '/' gt {
    return {
      type: 'html_tag',
      name: s.name,
      props: s.props,
      line: line(),
      column: column()
    };
  }

html_tag_start
  = lt n:key p:props
  {
    return {
      name: n,
      props: p
    };
  }

html_end_tag
  = lt '/' n:key gt { return n; }

props
  = p:(ws+ k:key "=" v:(js_expr / inline) {
    console.log("props", k, v);
    return { name: k, value: v, line: line(), column: column() };
  })*
//  { return ["params"].concat(p) }
//  = p:(ws+ k:key "=" v:(number / identifier / inline) { return ["param", ["literal", k], v]})*

/*-------------------------------------------------------------------------------------------------------------------------------------
   inline params is defined as matching two double quotes or double quotes plus literal followed by closing double quotes or
   double quotes plus inline_part followed by the closing double quotes
---------------------------------------------------------------------------------------------------------------------------------------*/
inline "inline"
  = '"' '"'                 { return ""; }
  / '"' l:literal '"'       { return l; }
//  / '"' p:inline_part+ '"'  { return ["body"].concat(p).concat([['line', line()], ['col', column()]]) }

/*-------------------------------------------------------------------------------------------------------------------------------------
   literal is defined as matching esc or any character except the double quotes and it cannot be a tag
---------------------------------------------------------------------------------------------------------------------------------------*/
literal "literal"
  = b:(!any_tag c:(esc / [^"]) {return c})+
  {
    console.log("literal", b.join(''));
    return b.join('')
  }

esc
  = '\\"' { return '"' }

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
    console.log("plain_text", b.join(''));
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
