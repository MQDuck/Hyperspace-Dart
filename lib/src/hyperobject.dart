/*
 * Copyright (C) 2019 Jeffrey Thomas Piercy
 *
 * This file is part of hyperspace.
 *
 * hyperspace is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * hyperspace is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with hyperspace.  If not, see <http://www.gnu.org/licenses/>.
 */

part of hyperspace;

class _EdgeIndices {
  int a, b;

  _EdgeIndices(this.a, this.b);

  String toString() {
    return '$a-$b';
  }
}

class Edge {
  Vector a, b;

  Edge(this.a, this.b);

  String toString() {
    return '$a --- $b';
  }
}

enum HyperobjectType { hypercube, hypersphere }

class Hyperobject {
  List<Vector> _vertices;
  List<Vector> _positionVertices;
  List<Vector> _drawingVertices;
  List<_EdgeIndices> _edges;
  Vector _translation;
  final _rotations;
  final _rotation_velocities;
  final Hyperspace _space;
  final HyperobjectType type;

  Hyperobject.hypercube(this._space, final double length, {int dimensions = -1})
      : _translation = Vector(_space),
        _rotations = _AxisPairMap(_space),
        _rotation_velocities = _AxisPairMap(_space),
        type = HyperobjectType.hypercube {
    if (dimensions < 0 || dimensions > _space._dimensions) {
      dimensions = _space._dimensions;
    }
    _vertices = List<Vector>(1 << dimensions);
    _positionVertices = List<Vector>(_vertices.length);
    _drawingVertices = List<Vector>(_vertices.length);
    _edges = List<_EdgeIndices>(dimensions * (1 << (dimensions - 1)));

    //var vertex = Vector.filled(space, -length / 2.0);
    var vertex = Vector(_space);
    for (int xi = 0; xi < dimensions; ++xi) {
      vertex[xi] = -length / 2.0;
    }
    _vertices[0] = vertex;

    var vi = 1;
    var ei = 0;

    for (int dim = 0; dim < dimensions; ++dim) {
      final numVertices = vi;
      final numEdges = ei;

      for (int i = 0; i < numEdges; ++i) {
        _edges[ei] = _EdgeIndices(_edges[i].a + numVertices, _edges[i].b + numVertices);
        ++ei;
      }

      for (int i = 0; i < numVertices; ++i) {
        _edges[ei] = _EdgeIndices(i, vi);
        ++ei;
        vertex = Vector.from(_space, _vertices[i]);
        vertex[dim] += length;
        _vertices[vi] = vertex;
        ++vi;
      }
    }
  }

  Hyperobject.hypersphere(this._space, final double radius, final int precision, {int dimensions = -1})
      : _translation = Vector(_space),
        _rotations = _AxisPairMap(_space),
        _rotation_velocities = _AxisPairMap(_space),
        type = HyperobjectType.hypersphere {
    if (dimensions < 0 || dimensions > _space._dimensions) {
      dimensions = _space._dimensions;
    }
    _vertices = List<Vector>(((dimensions * (dimensions - 1)) >> 1) * precision);
    _positionVertices = List<Vector>(_vertices.length);
    _drawingVertices = List<Vector>(_vertices.length);
    _edges = List<_EdgeIndices>(_vertices.length);

    final delta = 2.0 * pi / precision;
    int vi = 0;
    int ei = 0;
    for (int xa = 0; xa < dimensions - 1; ++xa) {
      for (int xb = xa + 1; xb < dimensions; ++xb) {
        for (int k = 0; k < precision; ++k) {
          final vertex = Vector(_space);
          vertex[xa] = cos(k * delta) * radius;
          vertex[xb] = sin(k * delta) * radius;
          _vertices[vi] = vertex;
          ++vi;
          if (k == precision - 1) {
            _edges[ei] = _EdgeIndices(vi - precision, vi - 1);
            ++ei;
          } else {
            _edges[ei] = _EdgeIndices(vi - 1, vi);
            ++ei;
          }
        }
      }
    }
  }

  void translate(Vector translation) => _translation += translation;

  void translateFromList(List<double> translation) => _translation += Vector.fromList(_space, translation);

  void setRotationVelocity(int xa, int xb, double theta) => _rotation_velocities.set(xa, xb, theta);

  void _update(double time) {
    var drawMatrix = TransformationMatrix.identity(_space);
    for (int xa = 0; xa < _space._dimensions - 1; ++xa) {
      for (int xb = xa + 1; xb < _space._dimensions; ++xb) {
        final theta = _rotations.get(xa, xb) + _rotation_velocities.get(xa, xb) * time;
        _rotations.set(xa, xb, theta);
        drawMatrix = TransformationMatrix.rotation(_space, xa, xb, theta) * drawMatrix;
      }
    }
    drawMatrix = TransformationMatrix.translation(_space, _translation + _space._globalTranslation) * drawMatrix;

    for (int i = 0; i < _vertices.length; ++i) {
      var vertex = drawMatrix.transform(_vertices[i]);
      vertex.setVisible();
      _positionVertices[i] = vertex;
      if (vertex.isVisible && _space.usePerspective) {
        _drawingVertices[i] = _space._perspectiveMatrix.transform(vertex);
      } else {
        _drawingVertices[i] = vertex;
      }
    }
  }

  List<double> getVertexList({final scaleX = 1.0, final scaleY = 1.0}) {
    final vertexList = List<double>(_drawingVertices.length << 1);
    for (int i = 0; i < _drawingVertices.length; ++i) {
      vertexList[i << 1] = scaleX * _drawingVertices[i].x;
      vertexList[(i << 1) + 1] = scaleY * _drawingVertices[i].y;
    }
    return vertexList;
  }

  List<int> getVisibleEdgeIndexList() {
    final edgeList = List<int>();
    for (final edge in _edges) {
      if (_drawingVertices[edge.a].isVisible && _drawingVertices[edge.b].isVisible) {
        edgeList.add(edge.a);
        edgeList.add(edge.b);
      }
    }
    return edgeList;
  }

  List<double> getDepthColorList() {
    final distances = List<double>(_drawingVertices.length);
    var maxDistance = 0.0;
    var minDistance = 1.0 / 0.0;
    for (int i = 0; i < _positionVertices.length; ++i) {
      if (_positionVertices[i].isVisible) {
        final distance = _positionVertices[i].distance(_space._viewerPosition);
        if (distance > maxDistance) {
          maxDistance = distance;
        }
        if (distance < minDistance) {
          minDistance = distance;
        }
        distances[i] = distance;
      } else {
        distances[i] = 0.0;
      }
    }

    final maxMinDiff = maxDistance - minDistance;
    final colorList = List<double>(distances.length * 3);
    for (int i = 0; i < distances.length; i += 1) {
      final relative = (distances[i] - minDistance) / maxMinDiff;
      colorList[3 * i] = 1.0 - relative;
      colorList[3 * i + 1] = 0.0;
      colorList[3 * i + 2] = relative;
    }
    return colorList;
  }

  int get numEdges => _edges.length;

  Edge getEdge(int index) => Edge(_drawingVertices[_edges[index].a], _drawingVertices[_edges[index].b]);
}
