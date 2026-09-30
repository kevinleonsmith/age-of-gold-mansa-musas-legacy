// Example React component for dynamic lines
const MansaDialogue = ({ gold }) => (
  <div className="p-4 bg-sand">
    {gold > 2000 ? (
      <p>"The world bends to Mali's golden will!"</p>
    ) : gold < 500 ? (
      <p>"Even dust holds value when properly gathered."</p>
    ) : (
      <p>"Balance in all things, as the scales decree."</p>
    )}
  </div>
);
