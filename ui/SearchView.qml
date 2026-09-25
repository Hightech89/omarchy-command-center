import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root
  property var controller
  signal activate(string actionId)
  function reveal() { if (controller && controller.selectedIndex >= 0) list.positionViewAtIndex(controller.selectedIndex, ListView.Contain) }
  function focusSearch() { Qt.callLater(function() { search.forceActiveFocus() }) }
  Column {
    anchors.fill: parent
    spacing: Style.spacing.md
    TextField {
      id: search
      width: parent.width
      placeholderText: "Search diagnostics and inspection tools"
      text: root.controller ? root.controller.searchQuery : ""
      onTextEdited: if (root.controller) root.controller.setSearchQuery(text)
      onAccepted: root.activate(root.controller.searchResults[root.controller.selectedIndex].id)
    }
    ListView {
      id: list
      width: parent.width; height: parent.height - search.height - Style.spacing.md
      clip: true; spacing: Style.spacing.xs
      model: root.controller ? root.controller.searchResults : []
      delegate: Button {
        required property var modelData
        width: ListView.view.width
        height: Style.space(42)
        selected: root.controller && index === root.controller.selectedIndex
        foreground: selected ? Color.menu.selectedText : Color.menu.text
        leftAlign: true
        text: modelData.name + "  ·  " + modelData.category + "\n" + modelData.description
        onHovered: function(on) { if (on && root.controller) root.controller.setSelectedIndex(index) }
        onClicked: root.activate(modelData.id)
      }
    }
  }
}
