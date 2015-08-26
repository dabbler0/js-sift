# Name
### kdt

# Synopsis
A node.js port of Ubilabs' pure javascript kd-tree library.

# Description
This is a fairly straightforward port of the simple & excellent [kd-tree javascript library](https://github.com/ubilabs/kd-tree-javascript) put together by Ubilabs. Their library can be used as-is in node, but this port changes its API to be more node-like and not require calling a `new` expression. It also wasn't on npm, and everything should be on npm.

# Example

```javascript
var kdt = require('./kdt')

var coords = [
  { name: 'Gramercy Theatre',
    loc: {lat: '40.739683', long: '73.985151'} },
  { name: 'Blue Note Jazz Club',
    loc: {lat: '40.730601', long: '74.000447'} },
  { name: 'Milk Studios',
    loc: {lat: '40.742256', long: '74.006344'} },
  { name: 'Greenroom Brooklyn',
    loc: {lat: '40.691805', long: '73.908089'} }
].map(function (v) {
  return v.loc
})

var distance = function(a, b){
  return Math.pow(a.lat - b.lat, 2) +  Math.pow(a.long - b.long, 2);
}

var tree = kdt.createKdTree(coords, distance, ['lat', 'long'])

var nearest = tree.nearest({ lat: 40, long: 75 }, 4);

console.log(nearest.reverse());
```