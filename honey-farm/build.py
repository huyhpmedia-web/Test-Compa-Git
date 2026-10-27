import pathlib,sys
d=pathlib.Path(__file__).parent
three=pathlib.Path(sys.argv[1]).read_text()
t=(d/'src/template.html').read_text()
g=(d/'src/game.js').read_text()
out=t.replace('/*THREE*/',"",1).replace('<script></script>','',1)
out=t.split('<script>/*THREE*/</script>')
out=out[0]+'<script>'+three.replace('</script','<\\/script')+'</script>'+out[1]
out=out.replace('<script>/*GAME*/</script>','<script>'+g+'</script>')
(d/'index.html').write_text(out)
print(len(out))
